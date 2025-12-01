# CloudKitUtilityPackage

**CloudKitUtilityPackage** — is a Swift library providing generic, async/await and Combine-based helpers for CloudKit. It simplifies CRUD operations, account checks, and notifications for entities conforming to ICloudEntity, offering a flexible and testable interface for the public CloudKit database.

The library is oriented toward the **publicCloudDatabase**, as it is intended for storing data that is accessible to all users of the application, without the need for a private database for a specific user.

![Swift iOS v15](https://img.shields.io/badge/Swift-iOS%20v15-0366d6?style=flat&logo=swift&logoColor=white)
![SPM](https://img.shields.io/badge/-SPM%20-0366d6?style=flat&logo=swift&logoColor=white&labelColor=555555)
![CloudKit](https://img.shields.io/badge/-CloudKit-0366d6?style=flat&logo=apple&logoColor=white&labelColor=555555)
![Combine](https://img.shields.io/badge/-Combine-0366d6?style=flat&logo=apple&logoColor=white&labelColor=555555)
![async/await](https://img.shields.io/badge/-async%2Fawait-0366d6?style=flat&logo=swift&logoColor=white&labelColor=555555)
![Unit Testing](https://img.shields.io/badge/-Unit%20Testing-0366d6?style=flat&logo=xcode&logoColor=white&labelColor=555555)

---

## Getting Started

```swift
import CloudKitUtilityPackage
...
var iCloudService = CloudKitUtilityPackage.shared
```

`CloudKitUtilityPackage.shared` is a singleton that provides a unified access point to the library’s functionality.

---

## Data Model Requirements

### `ICloudEntity`

```swift
protocol ICloudEntity: Hashable  {
    init?(record: CKRecord)
    var record: CKRecord { get }
}
```

**Overview:**
A protocol for data models that can be stored in CloudKit. It provides initialization from a `CKRecord` and the ability to generate a `CKRecord` for saving.

### `SortDescriptorWrapper`

```swift
struct SortDescriptorWrapper: Sendable {
    let key: String
    let ascending: Bool
}
```

**Overview:**
A thread-safe wrapper for `NSSortDescriptor` that allows sorting information to be safely passed between Swift concurrency contexts.

---

## Core Functions

### Проверка пользователя и информации о iCloud:

#### Combine-based:
---

```swift
func getAvailableiCloudAccountPublisher() -> AnyPublisher<Bool, Error>
```
**Overview:**
Checks if an iCloud account is available on the device.
```swift
func getUserIDPublisher() -> AnyPublisher<String, Error>
```
**Overview:**
Retrieves the current user's iCloud record ID.

#### Async/Await:
---

```swift
func getAvailableiCloudAccount() async throws -> Bool
```
**Overview:**
Checks if an iCloud account is available on the device.

```swift
func getUserInformation() async throws -> (id: String, name: String?)
```
**Overview:**
Retrieves the current iCloud user's record ID and, if available, their display name (may be `nil` due to Apple’s privacy restrictions).

---

### CRUD Functions:

#### Combine-based:
---

```swift
func createItemPublisher<T: ICloudEntity & Sendable>(item: T) -> AnyPublisher<CKRecord, Error>
```
**Overview:**
Creates a new CloudKit record from the given `ICloudEntity` and returns a publisher that emits the saved record or an error.

```swift
func readItem<T: ICloudEntity & Sendable>(recordID: CKRecord.ID) -> AnyPublisher<T?, Error>
```
**Overview:**
Fetches a CloudKit record by its CKRecord.ID and returns a publisher that emits the corresponding `ICloudEntity` (nil if initialization fails) or an error

```swift
func readItemsPublisher<T: ICloudEntity & Sendable>(
    recordType: CKRecord.RecordType,
    predicateBuilder: @escaping @Sendable () -> NSPredicate,
    sortDescriptors: [SortDescriptorWrapper]? = nil,
    resultsLimit: Int? = nil
) -> AnyPublisher<[T], Error>
```
**Overview:**
Fetches multiple CloudKit records matching the specified predicate and optional sort descriptors, returning a publisher that emits an array of `ICloudEntity` or an error.

```swift
func updateItemPublisher<T: ICloudEntity & Sendable>(item: T) -> AnyPublisher<CKRecord, Error>
```
**Overview:**
Updates an existing CloudKit record with the provided `ICloudEntity` and returns a publisher that emits the updated record or an error.

```swift
func deletePublisher<T: ICloudEntity & Sendable>(item: T) -> AnyPublisher<CKRecord.ID, Error>
```
**Overview:**
Deletes the specified CloudKit record and returns a publisher that emits the record ID of the deleted record or an error.

#### Async/Await:
---

```swift
func createItem<T: ICloudEntity>(item: T) async throws -> CKRecord
```
**Overview:**
Creates a new CloudKit record from the given `ICloudEntity` and returns the saved record, or throws an error if the save fails.

```swift
func readItem<T: ICloudEntity>(recordID: CKRecord.ID) async throws -> T?
```
**Overview:**
Fetches a CloudKit record by its CKRecord.ID and returns the corresponding `ICloudEntity` (nil if initialization fails), or throws an error.

```swift
func readItems<T: ICloudEntity & Sendable>(
    recordType: CKRecord.RecordType,
    predicateBuilder: @escaping () -> NSPredicate,
    sortDescriptors: [SortDescriptorWrapper]? = nil,
    resultsLimit: Int? = nil
) async throws -> [T]
```
**Overview:**
Fetches multiple CloudKit records matching the specified predicate and optional sort descriptors, returning an array of `ICloudEntity` or throws an error if the query fails.

```swift
func updateItem<T: ICloudEntity>(item: T) async throws -> CKRecord
```
**Overview:**
Updates an existing CloudKit record by saving the provided `ICloudEntity` (overwrites if it exists) and returns the updated record, or throws an error if the update fails.

```swift
func delete<T: ICloudEntity>(item: T) async throws -> CKRecord.ID
```
**Overview:**
Deletes the specified CloudKit record and returns the record ID of the deleted record, or throws an error if the deletion fails.

---

## Example Usage

### Async/Await:

```swift
do {
    // Check iCloud availability
    let isAvailable = try await CloudKitUtilityPackage.shared.getAvailableiCloudAccount()
    print("iCloud is available: \(isAvailable)")

    // Fetch user information
    let userInfo = try await CloudKitUtilityPackage.shared.getUserInformation()
    print("User ID: \(userInfo.id), Name: \(userInfo.name ?? "Unknown")")
    
    // Create a new entity
    let newItem = MyCloudEntity(...) // Must conform to ICloudEntity
    let createdRecord = try await CloudKitUtilityPackage.shared.createItem(item: newItem)
    
    // Fetch items with a filter
    let items: [MyCloudEntity] = try await CloudKitUtilityPackage.shared.readItems(
        recordType: "MyRecordType",
        predicateBuilder: { NSPredicate(format: "field == %@", argumentArray: ["value"]) },
        sortDescriptors: [CloudKitUtilityPackage.SortDescriptorWrapper(key: "date", ascending: false)]
    )
} catch {
    print("CloudKit error: \(error)")
}
```
### Combine-based:

```swift
import Combine

var cancellables = Set<AnyCancellable>()

// Check iCloud availability
CloudKitUtilityPackage.shared.getAvailableiCloudAccountPublisher()
    .sink { completion in
        if case let .failure(error) = completion {
            print("CloudKit error: \(error)")
        }
    } receiveValue: { isAvailable in
        print("iCloud is available: \(isAvailable)")
    }
    .store(in: &cancellables)

// Fetch user ID
CloudKitUtilityPackage.shared.getUserIDPublisher()
    .sink { completion in
        if case let .failure(error) = completion {
            print("CloudKit error: \(error)")
        }
    } receiveValue: { userID in
        print("User ID: \(userID)")
    }
    .store(in: &cancellables)

// Create a new entity
let newItem = MyCloudEntity(...)
CloudKitUtilityPackage.shared.createItemPublisher(item: newItem)
    .sink { completion in
        if case let .failure(error) = completion {
            print("CloudKit error: \(error)")
        }
    } receiveValue: { record in
        print("Created record: \(record)")
    }
    .store(in: &cancellables)

// Fetch items with a filter
CloudKitUtilityPackage.shared.readItemsPublisher(
    recordType: "MyRecordType",
    predicateBuilder: { NSPredicate(format: "field == %@", argumentArray: ["value"]) },
    sortDescriptors: [CloudKitUtilityPackage.SortDescriptorWrapper(key: "date", ascending: false)]
)
.sink { completion in
    if case let .failure(error) = completion {
        print("CloudKit error: \(error)")
    }
} receiveValue: { items in
    print("Fetched items: \(items)")
}
.store(in: &cancellables)
```

---

## Requirements

The library is compatible with the following environments:

- **iOS**: 15.0 and above
- **Swift**: 5.6 and above
- **CloudKit**: Public database access

> **Note:** This package is designed for `publicCloudDatabase` usage. For private or shared databases, adjustments may be required.

---

## License

**CloudKitUtilityPackage** is released under the **MIT License**.  

This allows you to freely use, modify, and distribute the code in your personal or commercial projects, provided that the original copyright notice and license are included.

- **Permission**: Granted to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software.  
- **Conditions**: Include the original license notice in all copies or substantial portions of the Software.  
- **Disclaimer**: The software is provided "as is", without warranty of any kind, express or implied.
