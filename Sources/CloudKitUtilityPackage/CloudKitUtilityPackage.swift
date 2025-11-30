//
//  CloudKitUtilityPackage.swift
//  SUI_Advanced_Learning
//
//  Created by Dmitriy Eliseev on 02.09.2025.
//

import Foundation
import Combine
import CloudKit
import UserNotifications

/// CloudKitUtilityPackage — a utility class providing generic methods for entities conforming to the ICloudEntity protocol.
public protocol ICloudEntity: Hashable  {
    init?(record: CKRecord)
    var record: CKRecord { get }
}

/// A utility class that provides a set of helper methods for interacting with CloudKit.
///
/// `CloudKitUtilityPackage` wraps common operations such as account status checking,
/// CRUD operations, and querying records, using both async/await and Combine-based APIs.
///
/// You can use this class via the shared singleton instance:
/// ```swift
/// let isAvailable = try await CloudKitUtilityPackage.shared.getAvailableiCloudAccount()
/// ```
///
/// - Note: This utility currently works with the public CloudKit database (`CKContainer.default().publicCloudDatabase`)
///
/// - Author: Eliseev Dmitry
/// - Since: 1.0.0

@MainActor
public final class CloudKitUtilityPackage {
    /// The CloudKit container used for all operations.
    /// By default, it is initialized with `CKContainer.default()`, but a custom container
    /// can be provided via the initializer, allowing for testing or using different iCloud containers.
    ///
    /// Using this container provides access to the three types of iCloud databases:
    /// - public (`publicCloudDatabase`)
    /// - private (`privateCloudDatabase`)
    /// - shared (`sharedCloudDatabase`)
    ///
    /// This design ensures flexibility in choosing the appropriate database for operations
    /// and enables dependency injection for better testability.
    private let container: CKContainer
    private let notificationCenter = UNUserNotificationCenter.current()
    public static let shared = CloudKitUtilityPackage()
    
    /// Private initializer for singleton with default container
    private init(container: CKContainer = .default()) {
        self.container = container
    }
    
    /// CloudKit-related errors used within the utility.
    enum CloudKitError: LocalizedError {
        case iCloudAccountNotFound
        case iCloudAccountNotDetermine
        case iCloudRestricted
        case iCloudAccountUnknown
        case iCloudAccountTemporarilyUnavailable
        case failedToInitializeModel
        case queryFailed
        
        var errorDescription: String? {
            switch self {
            case .iCloudAccountNotFound:
                return "iCloud account not found. Please sign in to iCloud in Settings."
            case .iCloudAccountNotDetermine:
                return "iCloud account status could not be determined. Try again later."
            case .iCloudRestricted:
                return "iCloud access is restricted. Some features may be unavailable."
            case .iCloudAccountUnknown:
                return "iCloud account status is unknown. Please check your settings."
            case .iCloudAccountTemporarilyUnavailable:
                return "iCloud account is temporarily unavailable. Please try again later."
            case .failedToInitializeModel:
                return "Failed to initialize the CloudKit model."
            case .queryFailed:
                return "The CloudKit query failed. Please try again."
            }
        }
    }
}

//MARK: - User Functions

// MARK: - User public functions (Combine-based)
extension CloudKitUtilityPackage {
    /// A Combine-based wrapper for checking the iCloud account status.
    /// Internally calls `getAvailableiCloudAccount()`, which may throw `CloudKitError`,
    /// and publishes a `Bool` indicating whether the iCloud account is available on the device.
    
    public func getAvailableiCloudAccountPublisher() -> AnyPublisher<Bool, Error> {
        Future { promise in
            Task {
                do {
                    let isAvailable = try await self.getAvailableiCloudAccount()
                    promise(.success(isAvailable))
                } catch {
                    promise(.failure(error))
                }
            }
        }
        .eraseToAnyPublisher()
    }
    
    /// A Combine-based wrapper for retrieving the current user's iCloud record id.
    /// This version only returns the unique user identifier (`recordName`), as Apple’s latest
    /// privacy policies often restrict access to user name and other identity information.
    public func getUserIDPublisher() -> AnyPublisher<String, Error> {
        Future { promise in
            Task {
                do {
                    let recordID = try await self.getUserRecordID()
                    promise(.success(recordID.recordName))
                } catch {
                    promise(.failure(error))
                }
            }
        }
        .eraseToAnyPublisher()
    }
}

// MARK: - User public functions (async/await)
extension CloudKitUtilityPackage {
    /// Checks whether the iCloud account is available using async/await.
    /// Returns `true` if the account status is `.available`, otherwise throws an appropriate `CloudKitError`.
    public func getAvailableiCloudAccount() async throws -> Bool {
        let accountStatus = try await getiCloudStatus()
        switch accountStatus {
        case .available:
            return true
        case .couldNotDetermine:
            throw CloudKitError.iCloudAccountNotDetermine
        case .restricted:
            throw CloudKitError.iCloudRestricted
        case .noAccount:
            throw CloudKitError.iCloudAccountNotFound
        case .temporarilyUnavailable:
            throw CloudKitError.iCloudAccountTemporarilyUnavailable
        @unknown default:
            throw CloudKitError.iCloudAccountUnknown
        }
    }
    
    /// Retrieves the current user’s iCloud ID and (if available) their name using async/await.
    ///
    /// While this function attempts to return the user's name, Apple’s recent privacy policy changes
    /// typically restrict access to personal identity data. In most cases, only the unique user ID is available.
    ///
    /// - Returns: A tuple containing the user ID and an optional name (if accessible).
    public func getUserInformation() async throws -> (id: String, name: String?) {
        let recordID = try await getUserRecordID()
        let participant = try await container.shareParticipant(forUserRecordID: recordID)
        var name: String?
        if let nameComponents = participant.userIdentity.nameComponents {
            name = PersonNameComponentsFormatter().string(from: nameComponents)
        } else {
            // The user's name is not accessible due to privacy settings.
            // This is expected behavior and does not indicate an error,
            // so we simply log it and return nil for the name.
            print("User name is hidden due to privacy settings.")
        }
        return (recordID.recordName, name)
    }
}

// MARK: - User private functions
extension CloudKitUtilityPackage {
    /// Fetches the current iCloud account status from the container.
    /// This is used internally to determine whether the iCloud account is active, restricted, or unavailable.
    private func getiCloudStatus() async throws -> CKAccountStatus {
        try await container.accountStatus()
    }
    
    /// Retrieves the current user's `CKRecord.ID` from the CloudKit container.
    /// This ID is a unique identifier for the user's iCloud record and is used in
    /// operations involving user-specific data or identity lookups.
    private func getUserRecordID() async throws -> CKRecord.ID {
        try await container.userRecordID()
    }
}

//MARK: - CRUD Functions

// MARK: - CRUD public functions (Combine-based)
extension CloudKitUtilityPackage {
    /// Creates (saves) a new CloudKit record from the provided model item.
    ///
    /// Wraps the asynchronous `createItem(item:)` method into a Combine publisher.
    ///
    /// - Parameter item: An instance conforming to `ICloudEntity` to be saved.
    /// - Returns: A publisher that outputs the saved `CKRecord?` on success,
    ///   or fails with an error if the save operation fails.
    public func createItemPublisher<T: ICloudEntity>(item: T) -> AnyPublisher<CKRecord?, Error> {
        Future { promise in
            Task {
                do {
                    let record = try await self.createItem(item: item)
                    promise(.success(record))
                } catch {
                    promise(.failure(error))
                }
            }
        }
        .eraseToAnyPublisher()
    }
    
    /// Fetches an entity conforming to `ICloudEntity` by its `CKRecord.ID` as a Combine publisher.
    ///
    /// This method is particularly useful when the model contains a `CKRecord.Reference?`
    /// and you need to fetch the referenced entity from another record.
    ///
    /// Internally, it wraps the async method `readItem(recordID:)` using a `Future`
    /// to provide a publisher that emits the fetched entity or an error.
    ///
    /// - Parameter recordID: The unique identifier of the CloudKit record to fetch.
    /// - Returns: A publisher that outputs an optional instance of the requested entity type,
    ///   or fails with an error if the record cannot be retrieved or initialized.
    public func readItem<T: ICloudEntity>(recordID: CKRecord.ID) -> AnyPublisher<T?, Error> {
        Future { promise in
            Task {
                do {
                    let item: T? = try await self.readItem(recordID: recordID)
                    promise(.success(item))
                } catch {
                    promise(.failure(error))
                }
            }
        }
        .eraseToAnyPublisher()
    }
    
    /// Fetches an array of model objects from CloudKit using a predicate generated by a closure,
    /// and exposes the results as a Combine publisher.
    ///
    /// This approach avoids `Sendable` issues by creating the `NSPredicate` inside the async context,
    /// rather than passing it from outside. The method wraps the async `readItems` function
    /// into a Combine `Future` to provide reactive stream-based access.
    ///
    /// - Parameters:
    ///   - recordType: The type of CloudKit records to fetch.
    ///   - predicateBuilder: A closure that generates an `NSPredicate` for filtering records.
    ///   - sortDescriptors: Optional array of `SortDescriptorWrapper`, safely converted into `NSSortDescriptor`.
    ///   - resultsLimit: Optional maximum number of records to fetch.
    /// - Returns: A publisher emitting an array of objects of type `T` matching the query, or failing with an error.
    public func readItemsPublisher<T: ICloudEntity & Sendable>(
        recordType: CKRecord.RecordType,
        predicateBuilder: @escaping () -> NSPredicate,
        sortDescriptors: [SortDescriptorWrapper]? = nil,
        resultsLimit: Int? = nil
    ) -> AnyPublisher<[T], Error> {
        Future { [self] promise in
            Task {
                do {
                    let items: [T] = try await readItems(
                        recordType: recordType,
                        predicateBuilder: predicateBuilder,
                        sortDescriptors: sortDescriptors,
                        resultsLimit: resultsLimit
                    )
                    promise(.success(items))
                } catch {
                    promise(.failure(error))
                }
            }
        }
        .eraseToAnyPublisher()
    }
    
    /// Updates an existing CloudKit record by saving the provided item.
    ///
    /// Currently implemented by calling the create operation (overwrite).
    /// This method wraps the `updateItem(item:)` async method into a Combine publisher,
    /// returning the saved `CKRecord?`.
    ///
    /// - Parameter item: The object conforming to `ICloudEntity` to update.
    /// - Returns: A publisher that outputs the updated `CKRecord?` on success,
    ///   or fails with an error if the update operation fails.
    public func updateItemPublisher<T: ICloudEntity>(item: T) -> AnyPublisher<CKRecord?, Error> {
        createItemPublisher(item: item)
    }
    
    /// Deletes a CloudKit record for the provided item from the public database.
    ///
    /// Wraps the asynchronous `delete(item:)` method into a Combine publisher.
    ///
    /// - Parameter item: The object to delete.
    /// - Returns: A publisher that emits the `CKRecord.ID` of the deleted record or an error.
    public func deletePublisher<T: ICloudEntity>(item: T) -> AnyPublisher<CKRecord.ID?, Error> {
        Future { promise in
            Task {
                do {
                    let recordID = try await self.delete(item: item)
                    promise(.success(recordID))
                } catch {
                    promise(.failure(error))
                }
            }
        }
        .eraseToAnyPublisher()
    }
}

// MARK: - CRUD public functions (async/await)
extension CloudKitUtilityPackage {
    /// Creates (saves) a new CloudKit record from the provided model item.
    ///
    /// Utilizes the `saveItem(record:)` method to save the record in the public database.
    ///
    /// - Parameter item: An instance conforming to `CloudKitableProtocol` to be saved.
    /// - Throws: Throws an error if saving the record to CloudKit fails.
    /// - Note: The method is marked `@discardableResult` so that the returned `CKRecord?`
    ///   does not trigger a compiler warning if it is not used.
    @discardableResult
    public func createItem<T: ICloudEntity>(item: T) async throws -> CKRecord? {
        let record = item.record
        return try await saveItem(record: record)
    }
    
    /// Retrieves an entity conforming to `ICloudEntity` by its `CKRecord.ID`.
    ///
    /// This method is particularly useful when the model contains a `CKRecord.Reference?`
    /// and you need to fetch the referenced entity from another record.
    ///
    /// The method internally uses the `record(for:)` extension on `CKDatabase`
    /// with `withCheckedThrowingContinuation` to maintain async/await semantics.
    ///
    /// - Parameter recordID: The unique identifier of the CloudKit record to fetch.
    /// - Returns: An optional instance of the requested entity type, or `nil` if the record cannot be initialized.
    public func readItem<T: ICloudEntity>(recordID: CKRecord.ID) async throws -> T? {
        let record = try await container.publicCloudDatabase.record(for: recordID)
        return T(record: record)
    }
    
    /// Fetches an array of model objects from CloudKit using a predicate generated by a closure.
    ///
    /// This approach avoids `Sendable` issues by creating the `NSPredicate` inside the async context,
    /// rather than passing it from outside.
    ///
    /// - Parameters:
    ///   - recordType: The type of CloudKit records to fetch.
    ///   - predicateBuilder: A closure that generates an `NSPredicate` for filtering records.
    ///   - sortDescriptors: Optional array of `SortDescriptorWrapper`, safely converted into `NSSortDescriptor`.
    ///   - resultsLimit: Optional maximum number of records to fetch.
    /// - Returns: An array of objects of type `T` matching the query.
    /// - Throws: Errors that may occur during query execution or while parsing records into model objects.
    public func readItems<T: ICloudEntity & Sendable>(
        recordType: CKRecord.RecordType,
        predicateBuilder: @escaping () -> NSPredicate,
        sortDescriptors: [SortDescriptorWrapper]? = nil,
        resultsLimit: Int? = nil
    ) async throws -> [T] {
        let stream: AsyncThrowingStream<T, Error> = try await fetchItemStream(
            predicate: predicateBuilder(),
            recordType: recordType,
            sortDescriptors: sortDescriptors,
            resultsLimit: resultsLimit
        )
        var items: [T] = []
        for try await item in stream {
            items.append(item)
        }
        return items
    }
    
    /// Updates an existing CloudKit record by saving the provided item.
    ///
    /// Currently implemented by calling the create operation (overwrite).
    ///
    /// - Parameter item: The object conforming to `ICloudEntity` to update.
    /// - Throws: Throws errors encountered while saving the record.
    /// - Note: The method is marked `@discardableResult` so that the returned `CKRecord?`
    ///   does not trigger a compiler warning if it is not used.
    @discardableResult
    public func updateItem<T: ICloudEntity>(item: T) async throws -> CKRecord? {
        try await createItem(item: item)
    }
    
    /// Deletes a CloudKit record for the provided item from the public database.
    ///
    /// - Parameter item: The object to delete.
    /// - Returns: The record ID of the deleted record.
    /// - Throws: Throws errors encountered during the deletion.
    public func delete<T: ICloudEntity>(item: T) async throws -> CKRecord.ID? {
        try await container.publicCloudDatabase.deleteRecord(withID: item.record.recordID)
    }
}

// MARK: - CRUD private functions
extension CloudKitUtilityPackage {
    /// A thread-safe, `Sendable` wrapper for `NSSortDescriptor`.
    ///
    /// Directly using `NSSortDescriptor` in asynchronous contexts (e.g., inside `AsyncThrowingStream` or Swift concurrency)
    /// is not guaranteed to be `Sendable`. This wrapper allows sorting information to be safely passed across concurrency boundaries.
    ///
    /// - Parameters:
    ///   - key: The record field key to sort by.
    ///   - ascending: Whether the sort order is ascending (`true`) or descending (`false`).
    struct SortDescriptorWrapper: Sendable {
        let key: String
        let ascending: Bool
    }
    
    /// Creates and returns an `AsyncThrowingStream` of model objects that match the given query parameters.
    ///
    /// Internally, this method configures a `CKQueryOperation` with the provided predicate,
    /// record type, optional sort descriptors, and result limit. It then attaches record-matching
    /// and query-result handlers to yield entities conforming to `ICloudEntity` as they are fetched.
    ///
    /// This helper abstracts away the setup of `CKQueryOperation` and exposes the results
    /// as an async sequence, making it easy to consume query results using Swift concurrency.
    ///
    /// - Parameters:
    ///   - predicate: An `NSPredicate` used to filter records.
    ///   - recordType: The CloudKit record type to query.
    ///   - sortDescriptors: Optional array of `SortDescriptorWrapper`, safely converted into `NSSortDescriptor`.
    ///   - resultsLimit: Optional maximum number of records to fetch.
    /// - Returns: An `AsyncThrowingStream` that yields entities of type `T` as they are retrieved.
    /// - Throws: Errors that may occur during operation creation or execution.
    private func fetchItemStream<T: ICloudEntity & Sendable>(
        predicate: NSPredicate,
        recordType: CKRecord.RecordType,
        sortDescriptors: [SortDescriptorWrapper]? = nil,
        resultsLimit: Int? = nil
    ) async throws -> AsyncThrowingStream<T, Error> {
        let ckSortDescriptors = sortDescriptors?.map { NSSortDescriptor(key: $0.key, ascending: $0.ascending) }
        let operation = createOperation(
            predicate: predicate,
            recordType: recordType,
            sortDescriptors: ckSortDescriptors,
            resultsLimit: resultsLimit
        )
        let stream: AsyncThrowingStream<T, any Error> = addRecordMatchedBlock(operation: operation)
        add(operation: operation)
        return stream
    }
    
    /// Adds the specified CloudKit database operation to the public database queue for execution.
    ///
    /// - Parameter operation: The CloudKit database operation to be executed.
    private func add(operation: CKDatabaseOperation) {
        container.publicCloudDatabase.add(operation)
    }
    
    /// Awaits the completion of a CKQueryOperation and returns a success boolean or throws an error.
    ///
    /// Wraps the callback-based `addQueryResultBlock` in an async context using a continuation.
    ///
    /// - Parameter operation: The query operation to observe.
    /// - Returns: True if the operation completed successfully.
    /// - Throws: An error if the operation fails.
    private func addQueryResultBlock(operation: CKQueryOperation) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            operation.queryResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume(returning: true)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Creates a CKQueryOperation configured with the given predicate, record type, optional sort descriptors, and optional result limit.
    ///
    /// - Parameters:
    ///   - predicate: The predicate to filter records.
    ///   - recordType: The type of records to query.
    ///   - sortDescriptors: Optional array of sort descriptors.
    ///   - resultsLimit: Optional maximum number of records to fetch.
    /// - Returns: A configured CKQueryOperation instance.
    private func createOperation(
        predicate: NSPredicate,
        recordType: CKRecord.RecordType,
        sortDescriptors: [NSSortDescriptor]? = nil,
        resultsLimit: Int? = nil
    ) -> CKQueryOperation {
        let query = CKQuery(recordType: recordType, predicate: predicate)
        query.sortDescriptors = sortDescriptors
        let queryOperation = CKQueryOperation(query: query)
        if let limit = resultsLimit {
            queryOperation.resultsLimit = limit
        }
        return queryOperation
    }
    
    /// Returns an AsyncThrowingStream that yields parsed model objects from matched CloudKit records.
    ///
    /// This stream allows asynchronous iteration over query results with error propagation.
    ///
    /// - Parameter operation: The CKQueryOperation to attach the record matched block to.
    /// - Returns: An AsyncThrowingStream yielding model objects of type `T`.
    private func addRecordMatchedBlock<T: ICloudEntity & Sendable>(
        operation: CKQueryOperation
    ) -> AsyncThrowingStream<T, Error> {
        AsyncThrowingStream { continuation in
            operation.recordMatchedBlock = { _, result in
                switch result {
                case .success(let record):
                    if let item = T(record: record) {
                        continuation.yield(item)
                    } else {
                        continuation.finish(throwing: CloudKitError.failedToInitializeModel)
                    }
                case .failure(let error):
                    continuation.finish(throwing: error)
                }
            }
            operation.queryResultBlock = { result in
                if case .failure(let error) = result {
                    continuation.finish(throwing: error)
                } else {
                    continuation.finish()
                }
            }
        }
    }
    
    /// Asynchronously saves a CloudKit record to the public database and returns the saved record.
    ///
    /// - Parameter record: The CKRecord to save.
    /// - Returns: The saved CKRecord as returned by CloudKit.
    /// - Throws: An error if saving the record fails.
    private func saveItem(record: CKRecord) async throws -> CKRecord {
        try await container.publicCloudDatabase.save(record)
    }
    
    private func handleRecordMatched<T: ICloudEntity>(
        result: Result<CKRecord, Error>,
        handler: (Result<T, Error>) -> Void
    ) {
        switch result {
        case .success(let record):
            if let item = T(record: record) {
                handler(.success(item))
            } else {
                handler(.failure(CloudKitError.failedToInitializeModel))
            }
        case .failure(let error):
            handler(.failure(error))
        }
    }
}

// MARK: - CRUD callback private functions
extension CloudKitUtilityPackage {
    /// Adds a recordMatchedBlock callback to a CKQueryOperation that returns results via a completion handler.
    ///
    /// Used for callback-style APIs or backward compatibility.
    ///
    /// - Parameters:
    ///   - operation: The CKQueryOperation to configure.
    ///   - completion: A completion handler returning a `Result` with either a model object or an error.
    private func addRecordMatchedBlock<T: ICloudEntity>(
        operation: CKQueryOperation,
        completion: @escaping (Result<T, Error>) -> Void
    ) {
        operation.recordMatchedBlock = { _, result in
            switch result {
            case .success(let record):
                if let item = T(record: record) {
                    completion(.success(item))
                } else {
                    completion(.failure(CloudKitError.failedToInitializeModel))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    /// Adds a queryResultBlock callback to a CKQueryOperation that returns success or failure via a completion handler.
    ///
    /// Used for callback-style APIs or backward compatibility.
    ///
    /// - Parameters:
    ///   - operation: The CKQueryOperation to observe.
    ///   - completion: A completion handler returning a `Result` with a success boolean or an error.
    private func addQueryResultBlock(
        operation: CKQueryOperation,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        operation.queryResultBlock = { result in
            switch result {
            case .success:
                completion(.success(true))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}

//НЕ ТЕСТИРОВАЛИ ЕЩЕ МЕТОДЫ!!!! ----------------------------------------------

// MARK: - Remote Notifications

// MARK: - Remote Notifications public functions (Combine-based)
extension CloudKitUtilityPackage {
    /// Requests authorization to display notifications, wrapped in a Combine publisher.
    ///
    /// - Parameter options: The authorization options to request.
    /// - Returns: A publisher emitting a Boolean indicating whether authorization was granted or an error if the request fails.
    public func requestNotificationPermissions(options: UNAuthorizationOptions) -> AnyPublisher<Bool, Error> {
        Future { promise in
            Task {
                do {
                    let result = try await self.requestNotificationPermissions(options: options)
                    promise(.success(result))
                } catch {
                    promise(.failure(error))
                }
            }
        }
        .eraseToAnyPublisher()
    }
    
    /// Subscribes to CloudKit notifications using the provided subscription, wrapped in a Combine publisher.
    ///
    /// - Parameter subscription: The `CKQuerySubscription` to save.
    /// - Returns: A publisher emitting the saved `CKSubscription` or an error if the operation fails.
    public func subscribeToNotifications(subscription: CKQuerySubscription) -> AnyPublisher<CKSubscription, Error> {
        Future { promise in
            Task {
                do {
                    let result = try await self.subscribeToNotifications(subscription: subscription)
                    promise(.success(result))
                } catch {
                    promise(.failure(error))
                }
            }
        }
        .eraseToAnyPublisher()
    }
    
    /// Unsubscribes from CloudKit notifications by deleting the subscription with the specified ID, wrapped in a Combine publisher.
    ///
    /// - Parameter subscriptionID: The ID of the subscription to delete.
    /// - Returns: A publisher emitting the deleted subscription ID or an error if the operation fails.
    public func unSubscribeToNotifications(subscriptionID: CKSubscription.ID) -> AnyPublisher<CKSubscription.ID, Error> {
        Future { promise in
            Task {
                do {
                    let result = try await self.unSubscribeToNotifications(subscriptionID: subscriptionID)
                    promise(.success(result))
                } catch {
                    promise(.failure(error))
                }
            }
        }
        .eraseToAnyPublisher()
    }
    
    /// Fetches all CloudKit subscriptions for the current user, wrapped in a Combine publisher.
    ///
    /// - Returns: A publisher emitting an array of `CKSubscription` or an error if the fetch fails.
    public func fetchAllSubscriptions() -> AnyPublisher<[CKSubscription], Error> {
        Future { promise in
            Task {
                do {
                    let result = try await self.fetchAllSubscriptions()
                    promise(.success(result))
                } catch {
                    promise(.failure(error))
                }
            }
        }
        .eraseToAnyPublisher()
    }
}

// MARK: - Remote Notifications public functions (async/await)
extension CloudKitUtilityPackage {
    /// Requests authorization to display notifications asynchronously.
    ///
    /// - Parameter options: The authorization options to request.
    /// - Returns: A Boolean indicating whether authorization was granted.
    /// - Throws: Throws an error if the authorization request fails.
    public func requestNotificationPermissions(options: UNAuthorizationOptions) async throws -> Bool {
        return try await notificationCenter.requestAuthorization(options: options)
    }
    
    /// Saves a CloudKit query subscription asynchronously to enable notifications.
    ///
    /// - Parameter subscription: The subscription to save.
    /// - Returns: The saved `CKSubscription`.
    /// - Throws: Throws an error if saving the subscription fails.
    public func subscribeToNotifications(subscription: CKQuerySubscription) async throws -> CKSubscription {
        return try await container.publicCloudDatabase.save(subscription)
    }
    
    /// Deletes a CloudKit subscription asynchronously to disable notifications.
    ///
    /// - Parameter subscriptionID: The ID of the subscription to delete.
    /// - Returns: The ID of the deleted subscription.
    /// - Throws: Throws an error if deleting the subscription fails.
    public func unSubscribeToNotifications(subscriptionID: CKSubscription.ID) async throws -> CKSubscription.ID {
        try await container.publicCloudDatabase.deleteSubscription(withID: subscriptionID)
    }
    
    /// Fetches all CloudKit subscriptions asynchronously.
    ///
    /// - Returns: An array of `CKSubscription` instances.
    /// - Throws: Throws an error if fetching subscriptions fails.
    public func fetchAllSubscriptions() async throws -> [CKSubscription] {
        try await withCheckedThrowingContinuation { continuation in
            fetchAllSubscriptions { result in
                switch result {
                case .success(let success):
                    continuation.resume(returning: success)
                case .failure(let failure):
                    continuation.resume(throwing: failure)
                }
            }
        }
    }
}

// MARK: - Remote Notifications private functions
extension CloudKitUtilityPackage {
    /// Fetches all CloudKit subscriptions using a completion handler.
    ///
    /// - Parameter completion: A closure called upon completion with a result containing an array of `CKSubscription` or an error.
    private func fetchAllSubscriptions(completion: @escaping @Sendable (Result<[CKSubscription], Error>) -> Void) {
        container.publicCloudDatabase.fetchAllSubscriptions { subscriptions, error in
            if let subscriptions = subscriptions {
                completion(.success(subscriptions))
            } else if let error = error {
                completion(.failure(error))
            } else {
                completion(.success([]))
            }
        }
    }
}


//extension CKDatabase {
//    func record(for recordID: CKRecord.ID) async throws -> CKRecord {
//        try await withCheckedThrowingContinuation { continuation in
//            self.fetch(withRecordID: recordID) { record, error in
//                if let error = error {
//                    continuation.resume(throwing: error)
//                } else if let record = record {
//                    continuation.resume(returning: record)
//                } else {
//                    continuation.resume(throwing: CloudKitUtilityPackage.CloudKitError.queryFailed)
//                }
//            }
//        }
//    }
//}
