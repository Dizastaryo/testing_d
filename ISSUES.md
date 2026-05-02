# SeeU Frontend — Full Issues & Improvements List

**Total: 177 issues**
Статус: `[ ]` = не сделано, `[+]` = исправлено

---

## CRITICAL (8)

- [+] C01. **auth_provider.dart** — `verifyOtp` catch-all создаёт mock-юзера при ЛЮБОЙ ошибке API, полностью обходя авторизацию
- [+] C02. **auth_provider.dart** — `sendOtp` catch-all всегда возвращает success, OTP "отправлен" даже без бэка
- [+] C03. **login_screen.dart** — Текст "Для тестирования введите 0000" виден в production UI — раскрывает тестовый OTP
- [+] C04. **create_post_screen.dart** — Нет реального image picker — посты используют picsum.photos placeholder URLs
- [+] C05. **comments_screen.dart** — `load()` без try/catch — любая ошибка API оставляет бесконечный спиннер (crash)
- [+] C06. **chat_provider.dart** — `Chat.fromJson` с `?? {}` вызовет crash при отсутствии `other_user`
- [+] C07. **camera_screen.dart** — Нет запроса разрешений камеры — на Android/iOS молча не работает
- [+] C08. **camera_screen.dart** — Нет обработки отсутствия камеры (web/desktop) — вечный спиннер

---

## HIGH — Bugs (28)

- [+] H01. **main.dart** — `ref` захвачен в closure GoRouter redirect — может быть вызван после dispose
- [+] H02. **main.dart** — Маршрут `/onboarding` нигде не вызывается — мёртвый код
- [+] H03. **main_scaffold.dart** — Все цвета навбара (surface, text, border) захардкожены под light тему
- [+] H04. **main_scaffold.dart** — `_NavIconPainter` использует `SeeUColors.textPrimary` без доступа к `BuildContext` — тёмная тема сломана
- [+] H05. **main_scaffold.dart** — Scanner FAB (80px) внутри Container (68px) без `clipBehavior: Clip.none` — обрезается
- [+] H06. **login_screen.dart** — OTP auto-verify при `code.length==4` может вызваться повторно при удалении/добавлении цифры
- [+] H07. **settings_screen.dart** — `logout()` не awaited перед `context.go('/login')` — race condition
- [+] H08. **onboarding_screen.dart** — Нет сохранения "onboarding seen" в SharedPreferences — показывается каждый раз
- [+] H09. **post_detail_screen.dart** — `Navigator.push` вместо `context.push` для CommentsScreen — ломает GoRouter навигацию
- [+] H10. **post_detail_screen.dart** — Комментарии рендерятся дважды — inline CommentsSection + отдельный CommentsScreen
- [+] H11. **auth_provider.dart** — `_loadInitial` не ставит `isLoading: true` — flash логин-экрана при старте с сохранённым токеном
- [+] H12. **feed_provider.dart** — `loadFeed` при ошибке очищает все посты вместо сохранения текущих
- [+] H13. **feed_provider.dart** — `toggleLike` читает пост ПОСЛЕ оптимистичного обновления — хрупкая логика
- [+] H14. **chat_provider.dart** — `sendMessage` — полностью пустая функция, сообщения не отправляются
- [+] H15. **user_provider.dart** — `searchNotifier.search` без debounce — десятки запросов при наборе текста
- [+] H16. **profile_screen.dart** — `isOwnProfile=true` когда `widget.username==null` даже если юзер не залогинен
- [+] H17. **profile_screen.dart** — "Написать" кнопка открывает список чатов, а не конкретный чат с юзером
- [+] H18. **edit_profile_screen.dart** — Avatar picker показывает "фото обновлено" snackbar без реального выбора фото
- [+] H19. **followers_screen.dart** — `_toggleFollow` оптимистично без await, без error handling, без rollback
- [+] H20. **chat_list_screen.dart** — Online статус определяется `user.id.hashCode % 3` — фейковый, не реальный
- [+] H21. **chat_screen.dart** — `_scrollToBottom` вызывается внутри `build()` — скролл на каждый rebuild
- [+] H22. **chat_screen.dart** — Typing indicator показывается когда ТЕКУЩИЙ юзер печатает, а не собеседник
- [+] H23. **chat_screen.dart** — Дистанция "12 м рядом" захардкожена как строка
- [+] H24. **stories_row.dart** — `_pageController` создан но НЕ привязан ни к одному PageView — все `animateToPage` вызовы крашатся
- [+] H25. **story_creator.dart** — Выбранное фото никогда не загружается — отправляется picsum URL
- [+] H26. **story_creator.dart** — GestureDetector `onTap` закрывает текстовый ввод при любом тапе включая TextField — редактирование невозможно
- [+] H27. **scanner_screen.dart** — `adapterState` stream subscription никогда не cancel'ится в dispose — memory leak
- [+] H28. **scanner_screen.dart** — Device dots используют `index * 51 + 30` для угла — при пересортировке списка точки телепортируются

---

## HIGH — Dark Theme (7)

- [+] D01. **tokens.dart** — Нет динамических алиасов для тёмной темы — все `SeeUColors.background/surface/text` всегда light
- [+] D02. **main.dart** — `statusBarIconBrightness: Brightness.dark` захардкожен — невидимый в тёмной теме
- [+] D03. **login_screen.dart** — `backgroundColor: SeeUColors.background` — light в тёмной теме
- [+] D04. **settings_screen.dart** — Все цвета карточек и секций захардкожены под light
- [+] D05. **onboarding_screen.dart** — Background и accent захардкожены
- [+] D06. **main_scaffold.dart** — Nav bar surface/border/icons все hardcoded light
- [+] D07. **notifications_screen.dart** — Background и карточки hardcoded light

---

## MEDIUM — Bugs & Logic (32)

- [+] M01. **camera_screen.dart** — `_isSwitching` навсегда `true` если `_setupCamera` бросает exception
- [+] M02. **camera_screen.dart** — `_flashMode` обновляется ДО `setFlashMode` — UI показывает неверную иконку при ошибке
- [+] M03. **camera_screen.dart** — Race condition: `_controller` может dispose'иться дважды при lifecycle + switch camera
- [+] M04. **camera_screen.dart** — `_takePicture` и `_buildShutterButton` оба вызывают `_shutterController.forward` одновременно
- [+] M05. **camera_screen.dart** — Aspect ratio формула `width / aspectRatio` некорректна для portrait устройств
- [+] M06. **camera_screen.dart** — `AnimatedOpacity` на zoom indicator не работает — widget условно добавлен в tree
- [+] M07. **scanner_screen.dart** — `_startScan` не оборачивает `startScan` в try/catch — crash при Bluetooth off
- [+] M08. **scanner_screen.dart** — `_personWord` всегда возвращает "человек" — нет склонения для 2-4
- [+] M09. **scanner_screen.dart** — Like кнопка в PersonSheet только закрывает sheet — никакого action
- [+] M10. **scanner_screen.dart** — `TweenAnimationBuilder` без key — анимация re-triggers при каждом BLE update
- [+] M11. **scanner_screen.dart** — `_fmtDist` может показать "0 м" для очень близких устройств
- [+] M12. **scanner_screen.dart** — Нет запроса Bluetooth permissions — на Android 12+ не работает
- [+] M13. **scanner_screen.dart** — `_chipOn` toggle чисто визуальный — BLE advertising не включается/выключается
- [+] M14. **stories_row.dart** — `_replyController.addListener` без removeListener в dispose — memory leak
- [+] M15. **stories_row.dart** — `_progressController.forward()` может быть вызван после dispose при navigation
- [+] M16. **stories_row.dart** — `ScaffoldMessenger.of(context)` в story viewer может найти wrong/stale Scaffold
- [+] M17. **stories_row.dart** — Long-press release вызывает и `onLongPressEnd` и `onTapUp` — story advance
- [+] M18. **post_card.dart** — Likes display "и ещё 0" когда `likesCount==1` с `likedByUsername`
- [+] M19. **post_card.dart** — `ScaffoldMessenger.of(context)` без mounted check после Navigator.pop
- [+] M20. **story_creator.dart** — `_isUploading` не сбрасывается на false при success — кнопка навечно disabled
- [+] M21. **story_creator.dart** — Draggable text overlay можно утащить за пределы экрана — нет bounds clamping
- [+] M22. **story_creator.dart** — `_textCtrl.text` в build() без listener — overlay не обновляется live
- [+] M23. **post_detail_screen.dart** — `ref.watch` внутри `FutureProvider` — может вызвать re-execution
- [+] M24. **post_detail_screen.dart** — `ScaffoldMessenger` после `Navigator.pop` — use-after-dispose risk
- [+] M25. **followers_screen.dart** — `ref.watch` внутри `FutureProvider`
- [+] M26. **comments_screen.dart** — `likeComment` не работает для reply (вложенных комментов)
- [+] M27. **comments_screen.dart** — `@mention` prefix в text field не привязан к `_replyToId` — inconsistency
- [+] M28. **notifications_screen.dart** — Счёт показывает total вместо filtered count
- [+] M29. **notifications_screen.dart** — Empty state при фильтре говорит "Нет уведомлений" вместо "Нет этого типа"
- [+] M30. **explore_screen.dart** — Masonry tall-item при `index%7==0` — первый пост ВСЕГДА tall
- [+] M31. **explore_screen.dart** — `_didScroll` check в build может зарегистрировать callback дважды
- [+] M32. **explore_screen.dart** — Comment input — фейковый Text widget, не TextField — невозможно писать

---

## MEDIUM — UX (25)

- [+] U01. **camera_screen.dart** — Gallery кнопка — no-op (`onTap: () {}`)
- [+] U02. **camera_screen.dart** — Flash кнопка активна на фронтальной камере — flash нет на фронталке
- [+] U03. **camera_screen.dart** — Нет feedback при failed takePicture — анимация есть, фото нет
- [+] U04. **camera_screen.dart** — Нет error state UI — только вечный спиннер при любой ошибке
- [+] U05. **scanner_screen.dart** — Нет сообщения "Bluetooth выключен" в radar view
- [+] U06. **scanner_screen.dart** — Like кнопка в list view — no-op
- [+] U07. **scanner_screen.dart** — Emoji для device зависит от index а не от MAC — меняется при пересортировке
- [+] U08. **feed_screen.dart** — Нет error state — если feed fetch failed, просто пустой экран
- [+] U09. **feed_screen.dart** — Empty state показывает "0" в 120px — непонятно юзеру
- [+] U10. **stories_row.dart** — `_timeAgo` возвращает "0m" для свежих историй вместо "только что"
- [+] U11. **story_creator.dart** — Нет пути из Camera swipe → Story creation — два disconnected entry points
- [+] U12. **story_creator.dart** — "Изменить" кнопка только gallery, нет retake camera
- [+] U13. **story_creator.dart** — Нет способа очистить/редактировать text overlay после ввода
- [+] U14. **post_card.dart** — Actions `_buildWaveActions` и `_buildActions` — дублирующийся код
- [+] U15. **post_card.dart** — Comments preview показывает только count, нет preview текста
- [+] U16. **profile_screen.dart** — "Add friend" icon button — no-op
- [+] U17. **profile_screen.dart** — Settings/BT кнопки видны на чужих профилях
- [+] U18. **edit_profile_screen.dart** — Username validator не проверяет формат (пробелы, спецсимволы)
- [+] U19. **chat_list_screen.dart** — New chat picker всегда показывает пустой список — feature broken
- [+] U20. **chat_screen.dart** — Back button `context.go('/chat')` ломает navigation stack
- [+] U21. **chat_screen.dart** — Plus/attachment кнопка — no-op
- [+] U22. **comments_screen.dart** — Клавиатура auto-opens при входе на экран — юзер не видит комментарии
- [+] U23. **comments_screen.dart** — Reply no-op в embedded CommentsSection
- [+] U24. **explore_screen.dart** — Error state без retry кнопки
- [+] U25. **explore_screen.dart** — Popular tags non-tappable — чисто декоративные

---

## MEDIUM — Performance (12)

- [+] P01. **camera_screen.dart** — `setState` на каждый frame pinch-to-zoom — full rebuild
- [+] P02. **scanner_screen.dart** — 3 AnimationController всегда repeat() даже когда radar не виден
- [+] P03. **scanner_screen.dart** — `_sortedDevices` getter — re-allocate + sort на каждый setState
- [+] P04. **scanner_screen.dart** — TweenAnimationBuilder в list view без key — flicker при scan updates
- [+] P05. **onboarding_screen.dart** — 9 AnimationController одновременно (3 slide x 3 pulse)
- [+] P06. **notifications_screen.dart** — `_buildItem` O(n^2) — итерирует Map на каждый itemBuilder вызов
- [+] P07. **notifications_screen.dart** — `ref.watch(authProvider)` без использования — лишний rebuild
- [+] P08. **chat_screen.dart** — `ListView(children: widgets)` вместо `ListView.builder` — нет виртуализации
- [+] P09. **chat_list_screen.dart** — `_filteredChats` пересчитывается на каждый build
- [+] P10. **user_provider.dart** — `loadProfile` 3 sequential API calls вместо `Future.wait`
- [+] P11. **profile_screen.dart** — Stat counter TweenAnimationBuilder начинает с 0 при каждом rebuild
- [+] P12. **explore_screen.dart** — `Random(42)` создаётся на каждый build

---

## LOW — UI/UX/Minor (18)

- [+] L01. **camera_screen.dart** — ClipRRect borderRadius:24 на fullscreen preview — некрасивые углы
- [+] L02. **camera_screen.dart** — Zoom indicator `bottom:180` hardcoded — на маленьких экранах overlap
- [+] L03. **scanner_screen.dart** — Distance labels hardcoded через `MediaQuery.size.height * 0.32` — не выровнены с кольцами
- [+] L04. **scanner_screen.dart** — FAB и bottom hint text overlap (bottom:100 vs bottom:90)
- [+] L05. **scanner_screen.dart** — Empty state radar `_pulseController` не в AnimatedBuilder.animation
- [+] L06. **scanner_screen.dart** — Sweep gradient radius 0.8 — не доходит до внешнего кольца
- [+] L07. **story_circle.dart** — Own story: container 68px но image 64px — 4px transparent gap без ring
- [+] L08. **story_circle.dart** — `_truncateUsername` manual + TextOverflow.ellipsis — двойное обрезание
- [+] L09. **post_card.dart** — Multi-image badge показывает иконку но не номер страницы (1/3)
- [+] L10. **register_screen.dart** — Бессмысленный экран — spinner на 1 frame + redirect
- [+] L11. **settings_screen.dart** — `Navigator.pop` вместо `context.pop` — inconsistent с GoRouter
- [+] L12. **settings_screen.dart** — Hardcoded username 'aidana_x' в privacy settings
- [+] L13. **main_scaffold.dart** — Bounce animation оставляет 1.1x scale навсегда после выбора
- [+] L14. **edit_profile_screen.dart** — `NetworkImage` вместо `CachedNetworkImage` для аватара
- [+] L15. **edit_profile_screen.dart** — 120px bottom padding — избыточный
- [+] L16. **notifications_screen.dart** — Нет loading state при начальной загрузке — сразу empty
- [+] L17. **tokens.dart** — `like` и `error` одинаковый цвет #FF3B6B — неразличимы
- [+] L18. **tokens.dart** — Typography styles `static` (mutable) вместо `static const`

---

## ARCHITECTURE (5)

- [+] A01. **tokens.dart** — Нет системы адаптации цветов к теме — все компоненты хардкодят light цвета
- [+] A02. **story_viewer.dart** — Stub-файл, вся логика в stories_row.dart (990 строк) — нужно разделить
- [+] A03. **story_creator.dart** — Импортирует api_client напрямую вместо MockService (нарушает архитектуру проекта)
- [+] A04. **explore_screen.dart** — ~600 строк мёртвого кода Reels (`_buildReelsGrid` и вся инфраструктура)
- [+] A05. **followers/following_screen.dart** — Copy-paste код — идентичные баги в обоих файлах
