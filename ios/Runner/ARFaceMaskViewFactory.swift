import Flutter
import UIKit
import ARKit
import SceneKit

// MARK: - Factory

class ARFaceMaskViewFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        return ARFaceMaskPlatformView(
            frame: frame,
            viewId: viewId,
            args: args as? [String: Any],
            messenger: messenger
        )
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}

// MARK: - Mask config parsed from Flutter params

private struct MaskConfig {
    let assetPath: String
    let anchor: String      // "eyes", "face", "lowerFace"
    let scale: Float        // width ratio: 1.0 = face width, 1.3 = 30% wider (e.g. glasses to ears)
    let offsetX: Float
    let offsetY: Float
    let offsetZ: Float      // extra forward gap (face-width units) ON TOP of auto-forward
    let rotationX: Float    // degrees
    let rotationY: Float
    let rotationZ: Float
    let occludeFace: Bool  // when true, skip occlusion geometry — mask renders fully in front

    init(from params: [String: Any]?) {
        assetPath   = params?["assetPath"] as? String ?? ""
        anchor      = params?["anchor"]    as? String ?? "face"
        scale       = Float(params?["scale"]     as? Double ?? 1.0)
        offsetX     = Float(params?["offsetX"]   as? Double ?? 0.0)
        offsetY     = Float(params?["offsetY"]   as? Double ?? 0.0)
        offsetZ     = Float(params?["offsetZ"]   as? Double ?? 0.0)
        rotationX   = Float(params?["rotationX"] as? Double ?? 0.0)
        rotationY   = Float(params?["rotationY"] as? Double ?? 0.0)
        rotationZ   = Float(params?["rotationZ"] as? Double ?? 0.0)
        occludeFace = params?["occludeFace"] as? Bool ?? false
    }

    var isHeadTop: Bool { anchor == "headTop" }

    var anchorOffsetY: Float {
        switch anchor {
        case "eyes":      return  0.015
        case "lowerFace": return -0.035
        case "headTop":   return  0.0   // handled specially in didUpdate
        default:          return  0.0
        }
    }
}

// MARK: - Platform View

class ARFaceMaskPlatformView: NSObject, FlutterPlatformView {
    private let arView: ARSCNView
    private let channel: FlutterMethodChannel
    private var preparedMask: SCNNode?
    private var config: MaskConfig
    private var sessionRunning = false

    /// Узел, который ARKit привязал к лицу (создаётся в `nodeFor`).
    /// ARKit зовёт `nodeFor` РОВНО ОДИН РАЗ на анкер, поэтому при смене маски
    /// новую модель некому было прикрепить — держим ссылку и пересобираем
    /// содержимое узла на месте.
    private weak var faceRootNode: SCNNode?

    // Model bounding-box info for adaptive scaling
    private var modelBBMaxDim: Float = 1.0
    private var modelBBWidth: Float = 1.0      // X-axis extent (ring diameter for crowns)
    private var modelBBHalfDepth: Float = 0.0
    private var modelBBHalfHeight: Float = 0.0

    // Smoothed face measurements (avoid jitter)
    private var smoothedFaceWidth: Float = 0.15
    private var smoothedNoseTipZ: Float = 0.025
    private var smoothedTopY: Float = 0.06
    private var smoothedMinZ: Float = -0.04
    private var hasMeasurement = false

    init(frame: CGRect, viewId: Int64, args: [String: Any]?, messenger: FlutterBinaryMessenger) {
        arView = ARSCNView(frame: frame)
        channel = FlutterMethodChannel(
            name: "seeu/ar_face_mask_\(viewId)",
            binaryMessenger: messenger
        )
        config = MaskConfig(from: args)
        super.init()

        arView.delegate = self
        arView.automaticallyUpdatesLighting = true
        arView.rendersContinuously = true
        arView.autoenablesDefaultLighting = true
        arView.antialiasingMode = .multisampling4X

        channel.setMethodCallHandler { [weak self] call, result in
            switch call.method {
            case "loadMask":
                let p = call.arguments as? [String: Any]
                self?.config = MaskConfig(from: p)
                self?.loadCurrentMask()
                result(nil)
            case "clearMask":
                self?.clearMask()
                result(nil)
            case "captureSnapshot":
                // Render the live AR scene (camera feed + 3D mask) to a JPEG so
                // Flutter can save it. Must run on the main thread.
                guard let self = self else {
                    result(FlutterError(code: "no_view", message: "AR view gone", details: nil))
                    return
                }
                let image = self.arView.snapshot()
                if let data = image.jpegData(compressionQuality: 0.92) {
                    result(FlutterStandardTypedData(bytes: data))
                } else {
                    result(FlutterError(code: "encode_failed",
                                        message: "Could not encode snapshot",
                                        details: nil))
                }
            default:
                result(FlutterMethodNotImplemented)
            }
        }

        startSession()
        loadCurrentMask()
    }

    func view() -> UIView { arView }

    // MARK: - AR Session

    private func startSession() {
        guard ARFaceTrackingConfiguration.isSupported else {
            NSLog("[ARFaceMask] Face tracking not supported on this device")
            channel.invokeMethod("onError", arguments: "Face tracking не поддерживается на этом устройстве")
            return
        }

        let cfg = ARFaceTrackingConfiguration()
        cfg.isLightEstimationEnabled = true
        cfg.maximumNumberOfTrackedFaces = 1
        arView.session.run(cfg, options: [.resetTracking, .removeExistingAnchors])
        sessionRunning = true

        NSLog("[ARFaceMask] AR session started")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.channel.invokeMethod("onReady", arguments: nil)
        }
    }

    // MARK: - Mask Loading + Auto-Normalization

    private func loadCurrentMask() {
        clearMask()
        guard !config.assetPath.isEmpty else { return }

        guard let flutterKey = lookupFlutterAssetKey(config.assetPath),
              let fileURL = Bundle.main.url(forResource: flutterKey, withExtension: nil) else {
            NSLog("[ARFaceMask] Asset not found: \(config.assetPath)")
            channel.invokeMethod("onError", arguments: "Маска не найдена: \(config.assetPath)")
            return
        }

        let rawNode: SCNNode
        do {
            rawNode = try GLBLoader.loadNode(from: fileURL)
        } catch {
            NSLog("[ARFaceMask] Failed to parse GLB: \(error)")
            channel.invokeMethod("onError", arguments: "Ошибка загрузки 3D модели: \(error.localizedDescription)")
            return
        }

        guard rawNode.childNodes.count > 0 else {
            NSLog("[ARFaceMask] No objects in GLB: \(config.assetPath)")
            channel.invokeMethod("onError", arguments: "Пустая 3D модель")
            return
        }

        // --- Step 1: Compute bounding box ---
        let (bbMin, bbMax) = rawNode.boundingBox
        let bbCenter = SCNVector3(
            (bbMin.x + bbMax.x) / 2,
            (bbMin.y + bbMax.y) / 2,
            (bbMin.z + bbMax.z) / 2
        )
        let bbWidth  = bbMax.x - bbMin.x
        let bbHeight = bbMax.y - bbMin.y
        let bbDepth  = bbMax.z - bbMin.z
        let bbMaxDim = max(bbWidth, max(bbHeight, bbDepth))

        guard bbMaxDim > 0 else {
            NSLog("[ARFaceMask] Model has zero bounding box")
            channel.invokeMethod("onError", arguments: "Модель имеет нулевой размер")
            return
        }

        NSLog("[ARFaceMask] BBox: w=\(bbWidth) h=\(bbHeight) d=\(bbDepth) center=(\(bbCenter.x),\(bbCenter.y),\(bbCenter.z))")

        // Store for adaptive per-frame updates
        modelBBMaxDim = bbMaxDim
        modelBBWidth = bbWidth
        modelBBHalfDepth = bbDepth / 2.0
        modelBBHalfHeight = bbHeight / 2.0

        // --- Step 2: Center at origin ---
        rawNode.position = SCNVector3(-bbCenter.x, -bbCenter.y, -bbCenter.z)

        // --- Step 3: Build container (initial transform, will be updated per frame) ---
        let container = SCNNode()
        container.name = "maskContainer"

        // Initial scale using default face width — will be overridden in didUpdate
        let defaultFaceWidth: Float = 0.15
        let autoScale = defaultFaceWidth / bbMaxDim
        let finalScale = autoScale * config.scale
        container.scale = SCNVector3(finalScale, finalScale, finalScale)
        container.position = SCNVector3(0, config.anchorOffsetY, 0.03)

        let degToRad = Float.pi / 180.0
        container.eulerAngles = SCNVector3(
            config.rotationX * degToRad,
            config.rotationY * degToRad,
            config.rotationZ * degToRad
        )

        container.addChildNode(rawNode)
        preparedMask = container

        // Reset smoothing
        hasMeasurement = false
        smoothedFaceWidth = defaultFaceWidth
        smoothedNoseTipZ = 0.025
        smoothedTopY = 0.06
        smoothedMinZ = -0.04

        NSLog("[ARFaceMask] Loaded '\(config.assetPath)' anchor=\(config.anchor) bbMaxDim=\(bbMaxDim) bbW=\(bbWidth) bbH=\(bbHeight) bbD=\(bbDepth)")

        // Лицо уже трекается — `nodeFor` больше не позовут, поэтому вешаем
        // новую модель в существующий узел сами. Без этого работала только
        // первая маска (та, что успевала подготовиться до появления анкера).
        if let root = faceRootNode {
            populateFaceRoot(root)
        }
    }

    /// Наполняет привязанный к лицу узел по ТЕКУЩЕМУ конфигу: окклюдер лица,
    /// череп-окклюдер для головных уборов и сама модель. Вызывается и при
    /// первом появлении лица (`nodeFor`), и при каждой смене маски.
    private func populateFaceRoot(_ root: SCNNode) {
        // Старое содержимое (окклюдеры + прошлая модель) убираем — конфиг
        // окклюзии зависит от маски и должен пересобираться вместе с ней.
        for child in root.childNodes {
            child.removeFromParentNode()
        }

        // 1) Occlusion geometry — invisible face that hides mask parts behind the head.
        //    Skip when occludeFace=true so the mask renders fully in front of the face.
        //    Skip for headTop — face depth buffer clips the front arc of crowns/hats.
        if !config.occludeFace, !config.isHeadTop,
           let device = arView.device,
           let faceGeo = ARSCNFaceGeometry(device: device, fillMesh: true) {
            let occlusionNode = SCNNode(geometry: faceGeo)
            occlusionNode.name = "occlusionNode"
            let mat = SCNMaterial()
            mat.colorBufferWriteMask = []   // Invisible: writes depth only
            mat.isDoubleSided = true
            occlusionNode.geometry?.firstMaterial = mat
            occlusionNode.renderingOrder = -1
            root.addChildNode(occlusionNode)
        }

        // 2) Skull occluder for headwear — ARSCNFaceGeometry only covers the
        //    face (forehead→chin). For crowns/hats that wrap around the head we
        //    need an invisible ellipsoid approximating the full skull so the back
        //    parts of the model are hidden behind the head.
        if config.isHeadTop {
            let sphere = SCNSphere(radius: 1.0) // unit sphere, scaled below
            sphere.segmentCount = 48
            let skullNode = SCNNode(geometry: sphere)
            skullNode.name = "skullOccluder"

            let mat = SCNMaterial()
            mat.colorBufferWriteMask = []   // depth-only, invisible
            mat.isDoubleSided = true
            sphere.firstMaterial = mat
            skullNode.renderingOrder = -1

            // Initial approximate size (updated per-frame in didUpdate to match
            // the measured head). Defaults assume faceWidth ≈ 0.15.
            let w: Float = 0.15
            skullNode.scale = SCNVector3(w * 0.62, w * 1.00, w * 0.75)
            skullNode.position = SCNVector3(0, w * 0.45, -w * 0.68)

            root.addChildNode(skullNode)
        }

        // 3) The 3D mask model (position/scale updated dynamically in didUpdate)
        if let mask = preparedMask?.clone() {
            mask.renderingOrder = 1
            root.addChildNode(mask)
        }
    }

    private func clearMask() {
        preparedMask = nil
        // Сам узел лица НЕ трогаем: его создал и держит ARKit под анкер, и
        // после его удаления `nodeFor` уже не позовут — маска не вернётся.
        // Чистим только содержимое.
        if let root = faceRootNode {
            for child in root.childNodes {
                child.removeFromParentNode()
            }
        }
    }

    private func lookupFlutterAssetKey(_ assetPath: String) -> String? {
        let key = FlutterDartProject.lookupKey(forAsset: assetPath)
        return key.isEmpty ? nil : key
    }
}

// MARK: - ARSCNViewDelegate

extension ARFaceMaskPlatformView: ARSCNViewDelegate {

    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        guard anchor is ARFaceAnchor else { return nil }

        let root = SCNNode()
        root.name = "faceMaskRoot"
        // Запоминаем: ARKit зовёт этот метод один раз на анкер, а маски
        // меняются много раз — дальше пересобираем содержимое сами.
        faceRootNode = root
        populateFaceRoot(root)
        return root
    }

    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let faceAnchor = anchor as? ARFaceAnchor else { return }

        // Update occlusion face geometry for mouth/eye movements
        for child in node.childNodes {
            if let faceGeo = child.geometry as? ARSCNFaceGeometry {
                faceGeo.update(from: faceAnchor.geometry)
            }
        }

        // --- Adaptive mask positioning based on real face measurements ---
        guard let maskContainer = node.childNodes.first(where: { $0.name == "maskContainer" }),
              modelBBMaxDim > 0 else { return }

        // Measure actual face width, top Y, nose tip Z, and back Z from face mesh vertices
        let vertices = faceAnchor.geometry.vertices
        var minX: Float = .infinity, maxX: Float = -.infinity
        var maxY: Float = -.infinity
        var maxZ: Float = -.infinity, minZ: Float = .infinity
        for i in 0..<vertices.count {
            let v = vertices[i]
            if v.x < minX { minX = v.x }
            if v.x > maxX { maxX = v.x }
            if v.y > maxY { maxY = v.y }
            if v.z > maxZ { maxZ = v.z }
            if v.z < minZ { minZ = v.z }
        }
        let rawFaceWidth = maxX - minX
        let rawNoseTipZ = maxZ

        guard rawFaceWidth > 0.01 else { return } // sanity

        // Smooth measurements to avoid jitter
        let alpha: Float = hasMeasurement ? 0.3 : 1.0
        smoothedFaceWidth = alpha * rawFaceWidth + (1 - alpha) * smoothedFaceWidth
        smoothedNoseTipZ  = alpha * rawNoseTipZ  + (1 - alpha) * smoothedNoseTipZ
        smoothedTopY      = alpha * maxY         + (1 - alpha) * smoothedTopY
        smoothedMinZ      = alpha * minZ         + (1 - alpha) * smoothedMinZ
        hasMeasurement = true

        // --- Adaptive scale ---
        let degToRad = Float.pi / 180.0
        let finalScale: Float

        if config.isHeadTop {
            // ── HEADWEAR: scale by model WIDTH so the ring/brim matches head width ──
            // Using bbMaxDim would shrink the ring if the model is taller than wide
            // (e.g. crown with spires). Scale by bbWidth = ring diameter.
            let autoScale = smoothedFaceWidth / modelBBWidth
            finalScale = autoScale * config.scale
        } else {
            // ── Face masks: scale by largest dimension (existing behaviour) ──
            let autoScale = smoothedFaceWidth / modelBBMaxDim
            finalScale = autoScale * config.scale
        }

        maskContainer.scale = SCNVector3(finalScale, finalScale, finalScale)

        maskContainer.eulerAngles = SCNVector3(
            config.rotationX * degToRad,
            config.rotationY * degToRad,
            config.rotationZ * degToRad
        )

        if config.isHeadTop {
            // ── HEADWEAR POSITIONING ─────────────────────────────────────────
            //
            // Face anchor origin = nose bridge (between the eyes).
            // ARKit face mesh: 1220 vertices, Y range ≈ -0.097…+0.089,
            //                  Z range ≈ -0.025…+0.070.
            // The mesh covers ONLY the front face (forehead→chin).
            // The back of the skull is NOT in the mesh.
            //
            // Head anatomy (adult average, from nose bridge):
            //   Top of forehead (maxY):  +8…+9 cm
            //   Top of skull:            +12…+13 cm
            //   Back of skull:           -14…-16 cm (Z)
            //   Head center depth:       ≈ -faceWidth × 0.5
            //
            // WEARING POINT: bottom edge of the crown/hat sits at the forehead.
            // We position the model so its BOTTOM (not center) is at the
            // forehead level, then apply cm-based offsets.
            //
            // headCenterZ: center of the skull ≈ half face width behind
            // the nose bridge. NOT based on noseTipZ (that's the nose tip
            // at Z≈+0.07, irrelevant to skull depth).

            // Y: model bottom edge sits at the top of the face mesh (forehead).
            let wearingPointY = smoothedTopY             // ≈ +0.089 m (forehead)
            let bottomOffset = modelBBHalfHeight * finalScale  // half model height
            let posY = wearingPointY + bottomOffset + config.offsetY * 0.01

            // Z: center of skull depth. Face mesh only covers the front;
            // actual skull extends ~faceWidth behind the face surface.
            let headCenterZ = -smoothedFaceWidth * 0.5   // ≈ -0.075 m
            let posZ = headCenterZ + config.offsetZ * 0.01

            let posX = config.offsetX * 0.01

            maskContainer.position = SCNVector3(posX, posY, posZ)

            // ── UPDATE SKULL OCCLUDER ────────────────────────────────────────
            // Ellipsoid approximating the HEAD + HAIR. The goal: the occluder's
            // on-screen silhouette must coincide with the real head outline, so
            // the back of the mask gets clipped exactly where the head is — not
            // as a tight "egg-shaped" arc on the forehead.
            //
            // A plain sphere is symmetric front-to-back; a real head is NOT —
            // the face is roughly flat/vertical in front, and the skull bulges
            // BACKWARD. So we push the ellipsoid back until its FRONT surface
            // sits at the face plane (Z≈0), and the bulk extends backward + up.
            // This stops the front of the ellipsoid bulging over the forehead.
            //
            // Sizing (relative to measured face width w), head + hair:
            //   Width:  1.24× face  (half = w × 0.62)  — ear to ear + hair
            //   Height: 2.0× face   (half = w × 1.00)  — jaw to above the hair
            //   Depth:  1.5× face   (half = w × 0.75)  — face to back of hair
            if let skullNode = node.childNodes.first(where: { $0.name == "skullOccluder" }) {
                let w = smoothedFaceWidth
                skullNode.scale = SCNVector3(
                    w * 0.62,   // half-width  (ear to ear + hair)
                    w * 1.00,   // half-height (raised, well above the crown)
                    w * 0.75    // half-depth  (face to back of hair)
                )
                // Center: raised ~6-7cm above the nose bridge, and pushed back so
                // the front pole lands on the face plane (front ≈ Zc + 0.75w ≈ 0).
                skullNode.position = SCNVector3(
                    0,
                    w * 0.45,    // raised — center well up into the skull
                    -w * 0.68    // pushed back — front surface ≈ face plane
                )
            }
        } else {
            // --- Face masks/glasses: sit in front of nose ---
            let modelDepthScaled = modelBBHalfDepth * finalScale
            let autoForwardZ = smoothedNoseTipZ + modelDepthScaled + 0.003

            maskContainer.position = SCNVector3(
                config.offsetX * smoothedFaceWidth,
                config.anchorOffsetY + config.offsetY * smoothedFaceWidth,
                autoForwardZ + config.offsetZ * smoothedFaceWidth
            )
        }
    }
}
