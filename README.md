# CloudKitUtilityPackage

**CloudKitUtilityPackage** — это Swift-библиотека, предоставляющая удобные асинхронные (`async/await`) и Combine-ориентированные функции для работы с CloudKit. Она упрощает CRUD-операции, проверку статуса iCloud-аккаунта и работу с уведомлениями для сущностей, которые соответствуют протоколу `ICloudEntity`.

Библиотека ориентирована на **publicCloudDatabase**, так как она предназначена для хранения данных, доступных всем пользователям приложения, без необходимости в приватной базе конкретного пользователя.

---

## Доступ к библиотеке

```swift
private var iCloudService = CloudKitUtilityPackage.shared
```

`CloudKitUtilityPackage.shared` — это **singleton**, предоставляющий общий доступ к функционалу библиотеки.

---

## Основные сущности

### `ICloudEntity`

```swift
public protocol ICloudEntity: Hashable  {
    init?(record: CKRecord)
    var record: CKRecord { get }
}
```

**Краткое описание:**
Протокол для моделей данных, которые могут быть сохранены в CloudKit. Обеспечивает инициализацию из `CKRecord` и возможность получения `CKRecord` для сохранения.

### `SortDescriptorWrapper`

```swift
public struct SortDescriptorWrapper: Sendable {
    let key: String
    let ascending: Bool
}
```

**Краткое описание:**
Потокобезопасная оболочка для `NSSortDescriptor`, позволяющая безопасно передавать информацию о сортировке между контекстами Swift concurrency.

---

## Основные функции

### Проверка пользователя и информации о iCloud

#### Combine-based

```swift
func getAvailableiCloudAccountPublisher() -> AnyPublisher<Bool, Error>
func getUserIDPublisher() -> AnyPublisher<String, Error>
```

#### Async/Await

```swift
func getAvailableiCloudAccount() async throws -> Bool
func getUserInformation() async throws -> (id: String, name: String?)
```

> `name` может быть `nil` в соответствии с политикой конфиденциальности Apple.

---

### CRUD функции

#### Combine-based

```swift
func createItemPublisher<T: ICloudEntity & Sendable>(item: T) -> AnyPublisher<CKRecord?, Error>
func readItem<T: ICloudEntity & Sendable>(recordID: CKRecord.ID) -> AnyPublisher<T?, Error>
func readItemsPublisher<T: ICloudEntity & Sendable>(
    recordType: CKRecord.RecordType,
    predicateBuilder: @escaping @Sendable () -> NSPredicate,
    sortDescriptors: [SortDescriptorWrapper]? = nil,
    resultsLimit: Int? = nil
) -> AnyPublisher<[T], Error> // Получение массива объектов из CloudKit с фильтром и сортировкой
func updateItemPublisher<T: ICloudEntity & Sendable>(item: T) -> AnyPublisher<CKRecord?, Error>
func deletePublisher<T: ICloudEntity & Sendable>(item: T) -> AnyPublisher<CKRecord.ID?, Error>
```

#### Async/Await

```swift
func createItem<T: ICloudEntity>(item: T) async throws -> CKRecord?
func readItem<T: ICloudEntity>(recordID: CKRecord.ID) async throws -> T?
func readItems<T: ICloudEntity & Sendable>(
    recordType: CKRecord.RecordType,
    predicateBuilder: @escaping () -> NSPredicate,
    sortDescriptors: [SortDescriptorWrapper]? = nil,
    resultsLimit: Int? = nil
) async throws -> [T] // Получение массива объектов из CloudKit с фильтром и сортировкой
func updateItem<T: ICloudEntity>(item: T) async throws -> CKRecord?
func delete<T: ICloudEntity>(item: T) async throws -> CKRecord.ID?
```

---

## Пример использования

```swift
// Async/Await
do {
    let isAvailable = try await iCloudService.getAvailableiCloudAccount()
    print("iCloud доступен: \(isAvailable)")

    let userInfo = try await iCloudService.getUserInformation()
    print("User ID: \(userInfo.id), Name: \(userInfo.name ?? "Unknown")")
    
    // Создание сущности
    let newItem = MyCloudEntity(...) // должен соответствовать ICloudEntity
    let createdRecord = try await iCloudService.createItem(item: newItem)
    
    // Получение объектов с фильтром
    let items: [MyCloudEntity] = try await iCloudService.readItems(
        recordType: "MyRecordType",
        predicateBuilder: { NSPredicate(format: "field == %@", argumentArray: ["value"]) },
        sortDescriptors: [SortDescriptorWrapper(key: "date", ascending: false)]
    )
} catch {
    print("Ошибка CloudKit: \(error)")
}
```

---

## Требования

- iOS 15+
- Swift 5.6+
- CloudKit

---

## Лицензия

MIT License
