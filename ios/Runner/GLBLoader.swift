import SceneKit
import Foundation

/// Self-contained GLB (glTF Binary 2.0) → SCNNode loader.
/// Handles meshes, PBR materials, and embedded textures.
/// No external dependencies — pure SceneKit + Foundation.
enum GLBLoader {

    enum GLBError: Error, LocalizedError {
        case invalidFile
        case invalidHeader
        case noJSONChunk
        case noBinaryChunk
        case invalidJSON
        case noMeshes
        case accessorOutOfBounds

        var errorDescription: String? {
            switch self {
            case .invalidFile:          return "Cannot read GLB file"
            case .invalidHeader:        return "Invalid GLB header"
            case .noJSONChunk:          return "No JSON chunk in GLB"
            case .noBinaryChunk:        return "No binary chunk in GLB"
            case .invalidJSON:          return "Invalid JSON in GLB"
            case .noMeshes:             return "No meshes found in GLB"
            case .accessorOutOfBounds:  return "Accessor out of bounds"
            }
        }
    }

    // MARK: - Public API

    /// Load a .glb file and return a SceneKit node tree.
    static func loadNode(from url: URL) throws -> SCNNode {
        let fileData = try Data(contentsOf: url)
        guard fileData.count >= 12 else { throw GLBError.invalidFile }

        // ── Parse GLB header ───────────────────────────────────────────────
        let magic   = fileData.readUInt32(at: 0)
        let version = fileData.readUInt32(at: 4)
        // let length  = fileData.readUInt32(at: 8)  // total file size (unused)

        guard magic == 0x46546C67, version == 2 else { // "glTF" in little-endian
            throw GLBError.invalidHeader
        }

        // ── Parse chunks ───────────────────────────────────────────────────
        var offset = 12
        var jsonData: Data?
        var binData: Data?

        while offset + 8 <= fileData.count {
            let chunkLen  = Int(fileData.readUInt32(at: offset))
            let chunkType = fileData.readUInt32(at: offset + 4)
            let chunkStart = offset + 8
            let chunkEnd   = chunkStart + chunkLen

            guard chunkEnd <= fileData.count else { break }

            let chunk = fileData.subdata(in: chunkStart..<chunkEnd)

            if chunkType == 0x4E4F534A { // "JSON"
                jsonData = chunk
            } else if chunkType == 0x004E4942 { // "BIN\0"
                binData = chunk
            }

            offset = chunkEnd
        }

        guard let json = jsonData else { throw GLBError.noJSONChunk }
        guard let bin  = binData  else { throw GLBError.noBinaryChunk }

        guard let gltf = try JSONSerialization.jsonObject(with: json) as? [String: Any] else {
            throw GLBError.invalidJSON
        }

        // ── Build scene from glTF JSON + binary buffer ─────────────────────
        return try buildScene(gltf: gltf, bin: bin)
    }

    // MARK: - Scene Builder

    private static func buildScene(gltf: [String: Any], bin: Data) throws -> SCNNode {
        let accessors   = gltf["accessors"]   as? [[String: Any]] ?? []
        let bufferViews = gltf["bufferViews"] as? [[String: Any]] ?? []
        let meshes      = gltf["meshes"]      as? [[String: Any]] ?? []
        let nodes       = gltf["nodes"]       as? [[String: Any]] ?? []
        let materials   = gltf["materials"]   as? [[String: Any]] ?? []
        let textures    = gltf["textures"]    as? [[String: Any]] ?? []
        let images      = gltf["images"]      as? [[String: Any]] ?? []
        let scenes      = gltf["scenes"]      as? [[String: Any]] ?? []
        let sceneIdx    = gltf["scene"]       as? Int ?? 0

        guard !meshes.isEmpty else { throw GLBError.noMeshes }

        // Pre-load images from binary buffer
        let loadedImages = images.map { img -> CGImage? in
            guard let bvIdx = img["bufferView"] as? Int,
                  bvIdx < bufferViews.count else { return nil }
            let bv = bufferViews[bvIdx]
            let byteOffset = bv["byteOffset"] as? Int ?? 0
            let byteLength = bv["byteLength"] as? Int ?? 0
            let imgData = bin.subdata(in: byteOffset..<(byteOffset + byteLength))
            guard let provider = CGDataProvider(data: imgData as CFData) else { return nil }
            // Try PNG first, then JPEG
            if let cgImg = CGImage(pngDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) {
                return cgImg
            }
            return CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        }

        // Build SCNMaterials
        let scnMaterials = materials.map { mat -> SCNMaterial in
            buildMaterial(mat, textures: textures, images: loadedImages)
        }

        // Build SCNNode for each glTF node
        var scnNodes: [SCNNode] = nodes.map { nodeDef -> SCNNode in
            let node = SCNNode()
            node.name = nodeDef["name"] as? String

            // Transform
            if let matrix = nodeDef["matrix"] as? [Double], matrix.count == 16 {
                node.transform = SCNMatrix4(
                    m11: Float(matrix[0]),  m12: Float(matrix[1]),  m13: Float(matrix[2]),  m14: Float(matrix[3]),
                    m21: Float(matrix[4]),  m22: Float(matrix[5]),  m23: Float(matrix[6]),  m24: Float(matrix[7]),
                    m31: Float(matrix[8]),  m32: Float(matrix[9]),  m33: Float(matrix[10]), m34: Float(matrix[11]),
                    m41: Float(matrix[12]), m42: Float(matrix[13]), m43: Float(matrix[14]), m44: Float(matrix[15])
                )
            } else {
                if let t = nodeDef["translation"] as? [Double], t.count == 3 {
                    node.position = SCNVector3(Float(t[0]), Float(t[1]), Float(t[2]))
                }
                if let r = nodeDef["rotation"] as? [Double], r.count == 4 {
                    node.orientation = SCNQuaternion(Float(r[0]), Float(r[1]), Float(r[2]), Float(r[3]))
                }
                if let s = nodeDef["scale"] as? [Double], s.count == 3 {
                    node.scale = SCNVector3(Float(s[0]), Float(s[1]), Float(s[2]))
                }
            }

            // Mesh
            if let meshIdx = nodeDef["mesh"] as? Int, meshIdx < meshes.count {
                let meshDef = meshes[meshIdx]
                if let geometry = buildGeometry(meshDef, accessors: accessors, bufferViews: bufferViews, bin: bin, materials: scnMaterials) {
                    node.geometry = geometry
                }
            }

            return node
        }

        // Build parent-child relationships
        for (i, nodeDef) in nodes.enumerated() {
            if let children = nodeDef["children"] as? [Int] {
                for childIdx in children where childIdx < scnNodes.count {
                    scnNodes[i].addChildNode(scnNodes[childIdx])
                }
            }
        }

        // Root node from scene
        let root = SCNNode()
        if sceneIdx < scenes.count, let sceneNodes = scenes[sceneIdx]["nodes"] as? [Int] {
            for idx in sceneNodes where idx < scnNodes.count {
                root.addChildNode(scnNodes[idx])
            }
        } else {
            // Fallback: add all root-level nodes
            for node in scnNodes {
                if node.parent == nil {
                    root.addChildNode(node)
                }
            }
        }

        return root
    }

    // MARK: - Geometry Builder

    private static func buildGeometry(
        _ meshDef: [String: Any],
        accessors: [[String: Any]],
        bufferViews: [[String: Any]],
        bin: Data,
        materials: [SCNMaterial]
    ) -> SCNGeometry? {
        guard let primitives = meshDef["primitives"] as? [[String: Any]] else { return nil }

        var sources = [SCNGeometrySource]()
        var elements = [SCNGeometryElement]()
        var geomMaterials = [SCNMaterial]()

        for prim in primitives {
            let attrs = prim["attributes"] as? [String: Int] ?? [:]

            // POSITION
            if let posIdx = attrs["POSITION"], let src = makeSource(posIdx, semantic: .vertex, accessors: accessors, bufferViews: bufferViews, bin: bin) {
                sources.append(src)
            }

            // NORMAL
            if let nrmIdx = attrs["NORMAL"], let src = makeSource(nrmIdx, semantic: .normal, accessors: accessors, bufferViews: bufferViews, bin: bin) {
                sources.append(src)
            }

            // TEXCOORD_0
            if let uvIdx = attrs["TEXCOORD_0"], let src = makeSource(uvIdx, semantic: .texcoord, accessors: accessors, bufferViews: bufferViews, bin: bin) {
                sources.append(src)
            }

            // Indices
            if let indicesIdx = prim["indices"] as? Int {
                if let elem = makeElement(indicesIdx, accessors: accessors, bufferViews: bufferViews, bin: bin) {
                    elements.append(elem)
                }
            }

            // Material
            if let matIdx = prim["material"] as? Int, matIdx < materials.count {
                geomMaterials.append(materials[matIdx])
            } else {
                geomMaterials.append(SCNMaterial()) // default
            }
        }

        guard !sources.isEmpty else { return nil }

        // If no indices, create a simple element
        if elements.isEmpty {
            if let posIdx = (primitives.first?["attributes"] as? [String: Int])?["POSITION"],
               posIdx < accessors.count {
                let count = accessors[posIdx]["count"] as? Int ?? 0
                let indices = (0..<count).map { UInt32($0) }
                let data = Data(bytes: indices, count: indices.count * 4)
                elements.append(SCNGeometryElement(data: data, primitiveType: .triangles, primitiveCount: count / 3, bytesPerIndex: 4))
            }
        }

        let geometry = SCNGeometry(sources: sources, elements: elements)
        geometry.materials = geomMaterials
        return geometry
    }

    private static func makeSource(
        _ accessorIdx: Int,
        semantic: SCNGeometrySource.Semantic,
        accessors: [[String: Any]],
        bufferViews: [[String: Any]],
        bin: Data
    ) -> SCNGeometrySource? {
        guard accessorIdx < accessors.count else { return nil }
        let acc = accessors[accessorIdx]

        guard let bvIdx = acc["bufferView"] as? Int, bvIdx < bufferViews.count else { return nil }
        let bv = bufferViews[bvIdx]

        let accOffset = acc["byteOffset"] as? Int ?? 0
        let bvOffset  = bv["byteOffset"]  as? Int ?? 0
        let count     = acc["count"]       as? Int ?? 0
        let compType  = acc["componentType"] as? Int ?? 5126 // FLOAT
        let type      = acc["type"]        as? String ?? "VEC3"

        let componentsPerVector: Int
        switch type {
        case "SCALAR": componentsPerVector = 1
        case "VEC2":   componentsPerVector = 2
        case "VEC3":   componentsPerVector = 3
        case "VEC4":   componentsPerVector = 4
        default:       componentsPerVector = 3
        }

        let bytesPerComponent: Int
        let floatComponents: Bool
        switch compType {
        case 5120: bytesPerComponent = 1; floatComponents = false  // BYTE
        case 5121: bytesPerComponent = 1; floatComponents = false  // UNSIGNED_BYTE
        case 5122: bytesPerComponent = 2; floatComponents = false  // SHORT
        case 5123: bytesPerComponent = 2; floatComponents = false  // UNSIGNED_SHORT
        case 5125: bytesPerComponent = 4; floatComponents = false  // UNSIGNED_INT
        case 5126: bytesPerComponent = 4; floatComponents = true   // FLOAT
        default:   bytesPerComponent = 4; floatComponents = true
        }

        let stride = bv["byteStride"] as? Int ?? (bytesPerComponent * componentsPerVector)
        let offset = bvOffset + accOffset
        let dataLength = count * stride

        guard offset + dataLength <= bin.count else { return nil }

        let data = bin.subdata(in: offset..<(offset + dataLength))

        return SCNGeometrySource(
            data: data,
            semantic: semantic,
            vectorCount: count,
            usesFloatComponents: floatComponents,
            componentsPerVector: componentsPerVector,
            bytesPerComponent: bytesPerComponent,
            dataOffset: 0,
            dataStride: stride
        )
    }

    private static func makeElement(
        _ accessorIdx: Int,
        accessors: [[String: Any]],
        bufferViews: [[String: Any]],
        bin: Data
    ) -> SCNGeometryElement? {
        guard accessorIdx < accessors.count else { return nil }
        let acc = accessors[accessorIdx]

        guard let bvIdx = acc["bufferView"] as? Int, bvIdx < bufferViews.count else { return nil }
        let bv = bufferViews[bvIdx]

        let accOffset = acc["byteOffset"] as? Int ?? 0
        let bvOffset  = bv["byteOffset"]  as? Int ?? 0
        let count     = acc["count"]       as? Int ?? 0
        let compType  = acc["componentType"] as? Int ?? 5123

        let bytesPerIndex: Int
        switch compType {
        case 5121: bytesPerIndex = 1  // UNSIGNED_BYTE
        case 5123: bytesPerIndex = 2  // UNSIGNED_SHORT
        case 5125: bytesPerIndex = 4  // UNSIGNED_INT
        default:   bytesPerIndex = 2
        }

        let offset = bvOffset + accOffset
        let dataLength = count * bytesPerIndex
        guard offset + dataLength <= bin.count else { return nil }

        let data = bin.subdata(in: offset..<(offset + dataLength))

        return SCNGeometryElement(
            data: data,
            primitiveType: .triangles,
            primitiveCount: count / 3,
            bytesPerIndex: bytesPerIndex
        )
    }

    // MARK: - Material Builder

    private static func buildMaterial(
        _ matDef: [String: Any],
        textures: [[String: Any]],
        images: [CGImage?]
    ) -> SCNMaterial {
        let mat = SCNMaterial()
        mat.lightingModel = .physicallyBased
        mat.isDoubleSided = matDef["doubleSided"] as? Bool ?? false

        // PBR Metallic Roughness
        if let pbr = matDef["pbrMetallicRoughness"] as? [String: Any] {
            // Base color
            if let bcTex = pbr["baseColorTexture"] as? [String: Any],
               let texIdx = bcTex["index"] as? Int {
                if let img = resolveTexture(texIdx, textures: textures, images: images) {
                    mat.diffuse.contents = img
                }
            } else if let bcFactor = pbr["baseColorFactor"] as? [Double], bcFactor.count >= 3 {
                mat.diffuse.contents = UIColor(
                    red: CGFloat(bcFactor[0]),
                    green: CGFloat(bcFactor[1]),
                    blue: CGFloat(bcFactor[2]),
                    alpha: bcFactor.count > 3 ? CGFloat(bcFactor[3]) : 1.0
                )
            }

            // Metallic
            mat.metalness.contents = NSNumber(value: pbr["metallicFactor"] as? Double ?? 0.0)

            // Roughness
            mat.roughness.contents = NSNumber(value: pbr["roughnessFactor"] as? Double ?? 1.0)

            // Metallic-Roughness texture
            if let mrTex = pbr["metallicRoughnessTexture"] as? [String: Any],
               let texIdx = mrTex["index"] as? Int {
                if let img = resolveTexture(texIdx, textures: textures, images: images) {
                    // glTF: R=unused, G=roughness, B=metallic
                    mat.metalness.contents = img
                    mat.metalness.textureComponents = .blue
                    mat.roughness.contents = img
                    mat.roughness.textureComponents = .green
                }
            }
        }

        // Normal map
        if let normalTex = matDef["normalTexture"] as? [String: Any],
           let texIdx = normalTex["index"] as? Int {
            if let img = resolveTexture(texIdx, textures: textures, images: images) {
                mat.normal.contents = img
            }
        }

        // Emissive
        if let emTex = matDef["emissiveTexture"] as? [String: Any],
           let texIdx = emTex["index"] as? Int {
            if let img = resolveTexture(texIdx, textures: textures, images: images) {
                mat.emission.contents = img
            }
        } else if let emFactor = matDef["emissiveFactor"] as? [Double], emFactor.count >= 3 {
            if emFactor[0] > 0 || emFactor[1] > 0 || emFactor[2] > 0 {
                mat.emission.contents = UIColor(
                    red: CGFloat(emFactor[0]),
                    green: CGFloat(emFactor[1]),
                    blue: CGFloat(emFactor[2]),
                    alpha: 1.0
                )
            }
        }

        // Alpha mode
        let alphaMode = matDef["alphaMode"] as? String ?? "OPAQUE"
        if alphaMode == "BLEND" {
            mat.transparencyMode = .dualLayer
            mat.blendMode = .alpha
        } else if alphaMode == "MASK" {
            mat.transparencyMode = .dualLayer
        }

        return mat
    }

    private static func resolveTexture(
        _ texIdx: Int,
        textures: [[String: Any]],
        images: [CGImage?]
    ) -> CGImage? {
        guard texIdx < textures.count else { return nil }
        let tex = textures[texIdx]
        guard let srcIdx = tex["source"] as? Int, srcIdx < images.count else { return nil }
        return images[srcIdx]
    }
}

// MARK: - Data helpers

private extension Data {
    func readUInt32(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return withUnsafeBytes { buf in
            buf.load(fromByteOffset: offset, as: UInt32.self)
        }
    }
}
