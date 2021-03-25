/*
 Copyright 2020 Adobe. All rights reserved.
 This file is licensed to you under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License. You may obtain a copy
 of the License at http://www.apache.org/licenses/LICENSE-2.0
 Unless required by applicable law or agreed to in writing, software distributed under
 the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
 OF ANY KIND, either express or implied. See the License for the specific language
 governing permissions and limitations under the License.
 */

import AEPCore
@testable import AEPIdentity
import AEPServices
import AEPServicesMocks
import XCTest

class IdentityStateTests: XCTestCase {
    var state: IdentityState!
    var mockHitQueue: MockHitQueue {
        return state.hitQueue as! MockHitQueue
    }
    
    var mockDataStore: MockDataStore {
        return ServiceProvider.shared.namedKeyValueService as! MockDataStore
    }

    var mockPushIdManager: MockPushIDManager!

    override func setUp() {
        ServiceProvider.shared.namedKeyValueService = MockDataStore()
        mockPushIdManager = MockPushIDManager()
        state = IdentityState(identityProperties: IdentityProperties(), hitQueue: MockHitQueue(processor: MockHitProcessor()), pushIdManager: mockPushIdManager)
    }

    // MARK: bootupIfReady(...) tests

    /// Tests that the properties are not update and we ignore the call
    func testBootupIfReadyEmptyConfigSharedState() {
        // test
        let result = state.bootupIfReady(configSharedState: [:], event: Event.fakeSyncIDEvent())

        // verify
        XCTAssertFalse(result)
        XCTAssertEqual(PrivacyStatus.unknown, state.identityProperties.privacyStatus)
        XCTAssertFalse(mockHitQueue.calledBeginProcessing && mockHitQueue.calledClear && mockHitQueue.calledSuspend) // privacy is unknown to only suspend the queue
    }

    /// Tests that the properties are updated, and the hit queue processes the change, and that shared state is create due to force sync
    func testBootupIfReadyWithOptInPrivacyReturnsTrue() {
        // setup
        let configSharedState = [IdentityConstants.Configuration.GLOBAL_CONFIG_PRIVACY: PrivacyStatus.optedIn, IdentityConstants.Configuration.EXPERIENCE_CLOUD_ORGID: "test-org-id"] as [String : Any]

        // test
        let result = state.bootupIfReady(configSharedState: configSharedState, event: Event.fakeSyncIDEvent())

        // verify
        XCTAssertTrue(result)
        XCTAssertEqual(PrivacyStatus.optedIn, state.identityProperties.privacyStatus) // privacy status should have been updated
        XCTAssertTrue(mockHitQueue.calledBeginProcessing) // opt-in should result in hit processing hits
    }

    /// Tests that the properties are updated, and the hit queue processes the change
    func testBootupIfReadyWithOptOutPrivacyReturnsTrue() {
        // setup
        let configSharedState = [IdentityConstants.Configuration.GLOBAL_CONFIG_PRIVACY: PrivacyStatus.optedOut, IdentityConstants.Configuration.EXPERIENCE_CLOUD_ORGID: "test-org-id"] as [String : Any]

        // test
        let result = state.bootupIfReady(configSharedState: configSharedState, event: Event.fakeSyncIDEvent())

        // verify
        XCTAssertTrue(result)
        XCTAssertEqual(PrivacyStatus.optedOut, state.identityProperties.privacyStatus) // privacy status should have been updated
        XCTAssertTrue(mockHitQueue.calledSuspend && mockHitQueue.calledClear) // opt-out should suspend and clear the queue
    }

    /// Tests that the properties are updated, and the hit queue processes the change, and that shared state is created from the force sync
    func testBootupIfReadyWithUnknownPrivacyReturnsFalse() {
        // setup
        let configSharedState = [IdentityConstants.Configuration.GLOBAL_CONFIG_PRIVACY: PrivacyStatus.unknown, IdentityConstants.Configuration.EXPERIENCE_CLOUD_ORGID: "test-org-id"] as [String : Any]

        // test
        let result = state.bootupIfReady(configSharedState: configSharedState, event: Event.fakeSyncIDEvent())

        // verify
        XCTAssertTrue(result)
        XCTAssertEqual(PrivacyStatus.unknown, state.identityProperties.privacyStatus) // privacy status should have been updated
        XCTAssertTrue(mockHitQueue.calledSuspend) // privacy is unknown to only suspend the queue
    }

    // MARK: syncIdentifiers(...) tests

    /// Tests that syncIdentifiers appends the ECID and the two custom IDs to the visitor ID list
    func testSyncIdentifiersHappyIDs() {
        // setup
        let configSharedState = [IdentityConstants.Configuration.EXPERIENCE_CLOUD_ORGID: "test-org",
                                 IdentityConstants.Configuration.EXPERIENCE_CLOUD_SERVER: "test-server",
                                 IdentityConstants.Configuration.GLOBAL_CONFIG_PRIVACY: PrivacyStatus.optedIn.rawValue] as [String: Any]
        state.lastValidConfig = configSharedState
        // test
        let eventData = state.syncIdentifiers(event: Event.fakeSyncIDEvent())

        // verify
        XCTAssertEqual(2, eventData!.count)
        XCTAssertNotNil(eventData![IdentityConstants.EventDataKeys.VISITOR_ID_ECID])
        let idList = eventData![IdentityConstants.EventDataKeys.VISITOR_IDS_LIST] as? [[String: Any]]
        XCTAssertEqual(2, idList?.count)
        XCTAssertFalse(mockHitQueue.queuedHits.isEmpty) // hit should be queued in the hit queue
    }

    /// Tests that syncIdentifiers returns nil and does not queue a hit when the user is opted-out
    func testSyncIdentifiersHappyIDsOptedOut() {
        // setup
        let configSharedState = [IdentityConstants.Configuration.EXPERIENCE_CLOUD_ORGID: "test-org",
                                 IdentityConstants.Configuration.EXPERIENCE_CLOUD_SERVER: "test-server",
                                 IdentityConstants.Configuration.GLOBAL_CONFIG_PRIVACY: PrivacyStatus.optedOut.rawValue] as [String: Any]
        state.lastValidConfig = configSharedState
        // test
        let eventData = state.syncIdentifiers(event: Event.fakeSyncIDEvent())

        // verify
        XCTAssertNil(eventData)
        XCTAssertTrue(mockHitQueue.queuedHits.isEmpty) // hit should NOT be queued in the hit queue
    }

    /// Tests that the push identifier is attached to the event data
    func testSyncIdentifiersHappyPushID() {
        // setup
        let configSharedState = [IdentityConstants.Configuration.EXPERIENCE_CLOUD_ORGID: "test-org",
                                 IdentityConstants.Configuration.EXPERIENCE_CLOUD_SERVER: "test-server",
                                 IdentityConstants.Configuration.GLOBAL_CONFIG_PRIVACY: PrivacyStatus.optedIn.rawValue] as [String: Any]
        state.lastValidConfig = configSharedState

        // test
        let eventData = state.syncIdentifiers(event: Event.fakePushIDEvent())

        // verify
        XCTAssertEqual(2, eventData!.count)
        XCTAssertNotNil(eventData![IdentityConstants.EventDataKeys.VISITOR_ID_ECID])
        XCTAssertEqual("test-push-id", eventData![IdentityConstants.EventDataKeys.PUSH_IDENTIFIER] as? String)
        XCTAssertFalse(mockHitQueue.queuedHits.isEmpty) // hit should be queued in the hit queue
    }

    /// Tests that the ECID is appended and the ad id is appended to the visitor id list
    func testSyncIdentifiersHappyAdID() {
        // setup
        let configSharedState = [IdentityConstants.Configuration.EXPERIENCE_CLOUD_ORGID: "test-org",
                                 IdentityConstants.Configuration.EXPERIENCE_CLOUD_SERVER: "test-server",
                                 IdentityConstants.Configuration.GLOBAL_CONFIG_PRIVACY: PrivacyStatus.optedIn.rawValue] as [String: Any]
        state.lastValidConfig = configSharedState

        // test
        let eventData = state.syncIdentifiers(event: Event.fakeAdIDEvent())

        // verify
        XCTAssertEqual(3, eventData!.count)
        XCTAssertNotNil(eventData![IdentityConstants.EventDataKeys.VISITOR_ID_ECID])
        XCTAssertEqual("test-ad-id", eventData![IdentityConstants.EventDataKeys.ADVERTISING_IDENTIFIER] as? String)
        let idList = eventData![IdentityConstants.EventDataKeys.VISITOR_IDS_LIST] as? [[String: Any]]
        XCTAssertEqual(1, idList?.count)
        let customId = idList?.first!

        XCTAssertEqual("test-ad-id", customId?[CustomIdentity.CodingKeys.identifier.rawValue] as? String)
        XCTAssertEqual("d_cid_ic", customId?[CustomIdentity.CodingKeys.origin.rawValue] as? String)
        XCTAssertEqual("DSID_20915", customId?[CustomIdentity.CodingKeys.type.rawValue] as? String)
        XCTAssertFalse(mockHitQueue.queuedHits.isEmpty) // hit should be queued in the hit queue
    }

    /// SetAdvertisingIdentifier with empty id and empty persisted id will not sync
    func testSyncIdentifiersAdIdDidNotChangeEmpty() {
        // setup
        let configSharedState = [IdentityConstants.Configuration.EXPERIENCE_CLOUD_ORGID: "test-org",
                                 IdentityConstants.Configuration.EXPERIENCE_CLOUD_SERVER: "test-server",
                                 IdentityConstants.Configuration.GLOBAL_CONFIG_PRIVACY: PrivacyStatus.optedIn.rawValue] as [String: Any]
        state.lastValidConfig = configSharedState
        state.identityProperties.advertisingIdentifier = ""
        state.identityProperties.lastSync = Date()
        state.identityProperties.ecid = ECID()

        // test
        let data = [IdentityConstants.EventDataKeys.ADVERTISING_IDENTIFIER: ""]
        let event = Event(name: "Fake Sync Event", type: EventType.genericIdentity, source: EventSource.requestReset, data: data)
        let eventData = state.syncIdentifiers(event: event)

        // verify
        XCTAssertEqual(3, eventData!.count)
        XCTAssertEqual("", eventData![IdentityConstants.EventDataKeys.ADVERTISING_IDENTIFIER] as? String)
        XCTAssertNil(eventData![IdentityConstants.EventDataKeys.VISITOR_IDS_LIST])
        XCTAssertTrue(mockHitQueue.queuedHits.isEmpty) // hit should NOT be queued in the hit queue
    }

    /// SetAdvertisingIdentifier with same id will not sync
    func testSyncIdentifiersAdIdDidNotChange() {
        // setup
        let configSharedState = [IdentityConstants.Configuration.EXPERIENCE_CLOUD_ORGID: "test-org",
                                 IdentityConstants.Configuration.EXPERIENCE_CLOUD_SERVER: "test-server",
                                 IdentityConstants.Configuration.GLOBAL_CONFIG_PRIVACY: PrivacyStatus.optedIn.rawValue] as [String: Any]
        state.lastValidConfig = configSharedState
        state.identityProperties.advertisingIdentifier = "test-ad-id"
        state.identityProperties.customerIds = [CustomIdentity(origin: "test-origin", type: "test-type", identifier: "test-id", authenticationState: .authenticated)]
        state.identityProperties.lastSync = Date()
        state.identityProperties.ecid = ECID()

        // test
        let data = [IdentityConstants.EventDataKeys.ADVERTISING_IDENTIFIER: "test-ad-id"]
        let event = Event(name: "Fake Sync Event", type: EventType.genericIdentity, source: EventSource.requestReset, data: data)
        let eventData = state.syncIdentifiers(event: event)

        // verify
        XCTAssertEqual(4, eventData!.count)
        XCTAssertEqual("test-ad-id", eventData![IdentityConstants.EventDataKeys.ADVERTISING_IDENTIFIER] as? String)
        let idList = eventData![IdentityConstants.EventDataKeys.VISITOR_IDS_LIST] as? [[String: Any]]
        XCTAssertEqual(1, idList?.count)
        let customId = idList?.first!
        XCTAssertEqual("test-id", customId?[CustomIdentity.CodingKeys.identifier.rawValue] as? String)
        XCTAssertEqual("test-origin", customId?[CustomIdentity.CodingKeys.origin.rawValue] as? String)
        XCTAssertEqual("test-type", customId?[CustomIdentity.CodingKeys.type.rawValue] as? String)
        XCTAssertTrue(mockHitQueue.queuedHits.isEmpty) // hit should NOT be queued in the hit queue
    }

    /// SetAdvertisingIdentifier with all zeros and empty persisted id will not sync
    func testSyncIdentifiersAdIdWithZeros() {
        // setup
        let configSharedState = [IdentityConstants.Configuration.EXPERIENCE_CLOUD_ORGID: "test-org",
                                 IdentityConstants.Configuration.EXPERIENCE_CLOUD_SERVER: "test-server",
                                 IdentityConstants.Configuration.GLOBAL_CONFIG_PRIVACY: PrivacyStatus.optedIn.rawValue] as [String: Any]
        state.lastValidConfig = configSharedState
        state.identityProperties.advertisingIdentifier = ""
        state.identityProperties.lastSync = Date()
        state.identityProperties.ecid = ECID()

        // test
        let data = [IdentityConstants.EventDataKeys.ADVERTISING_IDENTIFIER: IdentityConstants.Default.ZERO_ADVERTISING_ID]
        let event = Event(name: "Fake Sync Event", type: EventType.genericIdentity, source: EventSource.requestReset, data: data)
        let eventData = state.syncIdentifiers(event: event)

        // verify
        XCTAssertEqual(3, eventData!.count)
        XCTAssertEqual("", eventData![IdentityConstants.EventDataKeys.ADVERTISING_IDENTIFIER] as? String)
        XCTAssertNil(eventData![IdentityConstants.EventDataKeys.VISITOR_IDS_LIST])
        XCTAssertTrue(mockHitQueue.queuedHits.isEmpty) // hit should NOT be queued in the hit queue
    }

    /// Tests that the ad is is correctly updated when a new value is passed
    func testSyncIdentifiersAdIDIsUpdated() {
        // setup
        let configSharedState = [IdentityConstants.Configuration.EXPERIENCE_CLOUD_ORGID: "test-org",
                                 IdentityConstants.Configuration.EXPERIENCE_CLOUD_SERVER: "test-server",
                                 IdentityConstants.Configuration.GLOBAL_CONFIG_PRIVACY: PrivacyStatus.optedIn.rawValue] as [String: Any]
        var props = IdentityProperties()
        props.advertisingIdentifier = "old-test-ad-id"
        state = IdentityState(identityProperties: props, hitQueue: MockHitQueue(processor: MockHitProcessor()), pushIdManager: mockPushIdManager)
        state.lastValidConfig = configSharedState

        // test
        let eventData = state.syncIdentifiers(event: Event.fakeAdIDEvent())

        // verify
        XCTAssertEqual(3, eventData!.count)
        XCTAssertNotNil(eventData![IdentityConstants.EventDataKeys.VISITOR_ID_ECID])
        XCTAssertEqual("test-ad-id", eventData![IdentityConstants.EventDataKeys.ADVERTISING_IDENTIFIER] as? String)
        let idList = eventData![IdentityConstants.EventDataKeys.VISITOR_IDS_LIST] as? [[String: Any]]
        XCTAssertEqual(1, idList?.count)
        let customId = idList?.first!
        XCTAssertEqual("test-ad-id", customId?[CustomIdentity.CodingKeys.identifier.rawValue] as? String)
        XCTAssertEqual("d_cid_ic", customId?[CustomIdentity.CodingKeys.origin.rawValue] as? String)
        XCTAssertEqual("DSID_20915", customId?[CustomIdentity.CodingKeys.type.rawValue] as? String)
        XCTAssertFalse(mockHitQueue.queuedHits.isEmpty) // hit should be queued in the hit queue
        let hit = try! JSONDecoder().decode(IdentityHit.self, from: mockHitQueue.queuedHits.first!.data!)
        XCTAssertFalse(hit.url.absoluteString.contains("device_consent")) // device flag should NOT be added
    }

    /// Tests that the ad id is is correctly updated when a new value is passed
    func testSyncIdentifiersAdIDIsUpdatedFromEmpty() {
        // setup
        let configSharedState = [IdentityConstants.Configuration.EXPERIENCE_CLOUD_ORGID: "test-org",
                                 IdentityConstants.Configuration.EXPERIENCE_CLOUD_SERVER: "test-server",
                                 IdentityConstants.Configuration.GLOBAL_CONFIG_PRIVACY: PrivacyStatus.optedIn.rawValue] as [String: Any]
        var props = IdentityProperties()
        props.advertisingIdentifier = ""
        state = IdentityState(identityProperties: props, hitQueue: MockHitQueue(processor: MockHitProcessor()), pushIdManager: mockPushIdManager)
        state.lastValidConfig = configSharedState

        // test
        let eventData = state.syncIdentifiers(event: Event.fakeAdIDEvent())

        // verify
        XCTAssertEqual(3, eventData!.count)
        XCTAssertNotNil(eventData![IdentityConstants.EventDataKeys.VISITOR_ID_ECID])
        XCTAssertEqual("test-ad-id", eventData![IdentityConstants.EventDataKeys.ADVERTISING_IDENTIFIER] as? String)
        let idList = eventData![IdentityConstants.EventDataKeys.VISITOR_IDS_LIST] as? [[String: Any]]
        XCTAssertEqual(1, idList?.count)
        let customId = idList?.first!
        XCTAssertEqual("test-ad-id", customId?[CustomIdentity.CodingKeys.identifier.rawValue] as? String)
        XCTAssertEqual("d_cid_ic", customId?[CustomIdentity.CodingKeys.origin.rawValue] as? String)
        XCTAssertEqual("DSID_20915", customId?[CustomIdentity.CodingKeys.type.rawValue] as? String)
        XCTAssertFalse(mockHitQueue.queuedHits.isEmpty) // hit should be queued in the hit queue
        let hit = try! JSONDecoder().decode(IdentityHit.self, from: mockHitQueue.queuedHits.first!.data!)
        XCTAssertTrue(hit.url.absoluteString.contains("device_consent=1")) // device flag should be added
    }

    /// Tests that the ad id is correctly updated when a new value is passed (ad id changed from nil to valid value), hit is successfully queued and device_consent is set to 1.
    func testSyncIdentifiersAdIDIsUpdatedFromNil() {
        // setup
        let configSharedState = [IdentityConstants.Configuration.EXPERIENCE_CLOUD_ORGID: "test-org",
                                 IdentityConstants.Configuration.EXPERIENCE_CLOUD_SERVER: "test-server",
                                 IdentityConstants.Configuration.GLOBAL_CONFIG_PRIVACY: PrivacyStatus.optedIn.rawValue] as [String: Any]
        var props = IdentityProperties()
        props.advertisingIdentifier = nil
        state = IdentityState(identityProperties: props, hitQueue: MockHitQueue(processor: MockHitProcessor()), pushIdManager: mockPushIdManager)
        state.lastValidConfig = configSharedState

        // test
        let eventData = state.syncIdentifiers(event: Event.fakeAdIDEvent())

        // verify
        XCTAssertEqual(3, eventData!.count)
        XCTAssertNotNil(eventData![IdentityConstants.EventDataKeys.VISITOR_ID_ECID])
        XCTAssertEqual("test-ad-id", eventData![IdentityConstants.EventDataKeys.ADVERTISING_IDENTIFIER] as? String)
        let idList = eventData![IdentityConstants.EventDataKeys.VISITOR_IDS_LIST] as? [[String: Any]]
        XCTAssertEqual(1, idList?.count)
        let customId = idList?.first!
        XCTAssertEqual("test-ad-id", customId?[CustomIdentity.CodingKeys.identifier.rawValue] as? String)
        XCTAssertEqual("d_cid_ic", customId?[CustomIdentity.CodingKeys.origin.rawValue] as? String)
        XCTAssertEqual("DSID_20915", customId?[CustomIdentity.CodingKeys.type.rawValue] as? String)
        XCTAssertFalse(mockHitQueue.queuedHits.isEmpty) // hit should be queued in the hit queue
        let hit = try! JSONDecoder().decode(IdentityHit.self, from: mockHitQueue.queuedHits.first!.data!)
        XCTAssertTrue(hit.url.absoluteString.contains("device_consent=1")) // device flag should be added
    }

    /// Tests that the ad is is correctly updated when a new value is passed
    func testSyncIdentifiersAdIDIsUpdatedFromZeroString() {
        // setup
        let configSharedState = [IdentityConstants.Configuration.EXPERIENCE_CLOUD_ORGID: "test-org",
                                 IdentityConstants.Configuration.EXPERIENCE_CLOUD_SERVER: "test-server",
                                 IdentityConstants.Configuration.GLOBAL_CONFIG_PRIVACY: PrivacyStatus.optedIn.rawValue] as [String: Any]
        var props = IdentityProperties()
        props.advertisingIdentifier = IdentityConstants.Default.ZERO_ADVERTISING_ID
        state = IdentityState(identityProperties: props, hitQueue: MockHitQueue(processor: MockHitProcessor()), pushIdManager: mockPushIdManager)
        state.lastValidConfig = configSharedState

        // test
        let eventData = state.syncIdentifiers(event: Event.fakeAdIDEvent())

        // verify
        XCTAssertEqual(3, eventData!.count)
        XCTAssertNotNil(eventData![IdentityConstants.EventDataKeys.VISITOR_ID_ECID])
        XCTAssertEqual("test-ad-id", eventData![IdentityConstants.EventDataKeys.ADVERTISING_IDENTIFIER] as? String)
        let idList = eventData![IdentityConstants.EventDataKeys.VISITOR_IDS_LIST] as? [[String: Any]]
        XCTAssertEqual(1, idList?.count)
        let customId = idList?.first!
        XCTAssertEqual("test-ad-id", customId?[CustomIdentity.CodingKeys.identifier.rawValue] as? String)
        XCTAssertEqual("d_cid_ic", customId?[CustomIdentity.CodingKeys.origin.rawValue] as? String)
        XCTAssertEqual("DSID_20915", customId?[CustomIdentity.CodingKeys.type.rawValue] as? String)
        XCTAssertFalse(mockHitQueue.queuedHits.isEmpty) // hit should be queued in the hit queue
        let hit = try! JSONDecoder().decode(IdentityHit.self, from: mockHitQueue.queuedHits.first!.data!)
        XCTAssertTrue(hit.url.absoluteString.contains("device_consent=1")) // device flag should be added
    }

    /// Tests that the ad is is correctly updated when a new value is passed
    func testSyncIdentifiersAdIDIsUpdatedFromValidToEmpty() {
        // setup
        let configSharedState = [IdentityConstants.Configuration.EXPERIENCE_CLOUD_ORGID: "test-org",
                                 IdentityConstants.Configuration.EXPERIENCE_CLOUD_SERVER: "test-server",
                                 IdentityConstants.Configuration.GLOBAL_CONFIG_PRIVACY: PrivacyStatus.optedIn.rawValue] as [String: Any]
        var props = IdentityProperties()
        props.advertisingIdentifier = "test-ad-id"
        state = IdentityState(identityProperties: props, hitQueue: MockHitQueue(processor: MockHitProcessor()), pushIdManager: mockPushIdManager)
        state.lastValidConfig = configSharedState

        // test
        let data = [IdentityConstants.EventDataKeys.ADVERTISING_IDENTIFIER: ""]
        let event = Event(name: "Fake Sync Event", type: EventType.genericIdentity, source: EventSource.requestReset, data: data)
        let eventData = state.syncIdentifiers(event: event)

        // verify
        XCTAssertEqual(2, eventData!.count)
        XCTAssertNotNil(eventData![IdentityConstants.EventDataKeys.VISITOR_ID_ECID])
        XCTAssertEqual("", eventData![IdentityConstants.EventDataKeys.ADVERTISING_IDENTIFIER] as? String)
        XCTAssertNil(eventData![IdentityConstants.EventDataKeys.VISITOR_IDS_LIST])
        XCTAssertFalse(mockHitQueue.queuedHits.isEmpty) // hit should be queued in the hit queue
        let hit = try! JSONDecoder().decode(IdentityHit.self, from: mockHitQueue.queuedHits.first!.data!)
        XCTAssertTrue(hit.url.absoluteString.contains("device_consent=0")) // device flag should be added
        XCTAssertTrue(hit.url.absoluteString.contains("d_consent_ic=DSID_20915")) // id namespace should be added
    }

    /// Tests that the ad is is correctly updated when a new value is passed
    func testSyncIdentifiersAdIDIsUpdatedFromValidToZeroString() {
        // setup
        let configSharedState = [IdentityConstants.Configuration.EXPERIENCE_CLOUD_ORGID: "test-org",
                                 IdentityConstants.Configuration.EXPERIENCE_CLOUD_SERVER: "test-server",
                                 IdentityConstants.Configuration.GLOBAL_CONFIG_PRIVACY: PrivacyStatus.optedIn.rawValue] as [String: Any]
        var props = IdentityProperties()
        props.advertisingIdentifier = "test-ad-id"
        state = IdentityState(identityProperties: props, hitQueue: MockHitQueue(processor: MockHitProcessor()), pushIdManager: mockPushIdManager)
        state.lastValidConfig = configSharedState

        // test
        let data = [IdentityConstants.EventDataKeys.ADVERTISING_IDENTIFIER: IdentityConstants.Default.ZERO_ADVERTISING_ID]
        let event = Event(name: "Fake Sync Event", type: EventType.genericIdentity, source: EventSource.requestReset, data: data)
        let eventData = state.syncIdentifiers(event: event)

        // verify
        XCTAssertEqual(2, eventData!.count)
        XCTAssertNotNil(eventData![IdentityConstants.EventDataKeys.VISITOR_ID_ECID])
        XCTAssertEqual("", eventData![IdentityConstants.EventDataKeys.ADVERTISING_IDENTIFIER] as? String)
        XCTAssertNil(eventData![IdentityConstants.EventDataKeys.VISITOR_IDS_LIST])
        XCTAssertFalse(mockHitQueue.queuedHits.isEmpty) // hit should be queued in the hit queue
        let hit = try! JSONDecoder().decode(IdentityHit.self, from: mockHitQueue.queuedHits.first!.data!)
        XCTAssertTrue(hit.url.absoluteString.contains("device_consent=0")) // device flag should be added
        XCTAssertTrue(hit.url.absoluteString.contains("d_consent_ic=DSID_20915")) // id namespace should be added
    }

    /// When we currently have a nil ad id and update to an empty ad id we should sync with the device consent flag set to 0
    func testSyncIdentifiersAdIDIsUpdatedFromZerosToEmpty() {
        // setup
        let configSharedState = [IdentityConstants.Configuration.EXPERIENCE_CLOUD_ORGID: "test-org",
                                 IdentityConstants.Configuration.EXPERIENCE_CLOUD_SERVER: "test-server",
                                 IdentityConstants.Configuration.GLOBAL_CONFIG_PRIVACY: PrivacyStatus.optedIn.rawValue] as [String: Any]
        var props = IdentityProperties()
        props.advertisingIdentifier = IdentityConstants.Default.ZERO_ADVERTISING_ID
        props.ecid = ECID()
        props.lastSync = Date()
        state = IdentityState(identityProperties: props, hitQueue: MockHitQueue(processor: MockHitProcessor()), pushIdManager: mockPushIdManager)
        state.lastValidConfig = configSharedState

        // test
        let data = [IdentityConstants.EventDataKeys.ADVERTISING_IDENTIFIER: ""]
        let event = Event(name: "Fake Sync Event", type: EventType.genericIdentity, source: EventSource.requestReset, data: data)
        let eventData = state.syncIdentifiers(event: event)

        // verify
        XCTAssertEqual(3, eventData!.count)
        XCTAssertNotNil(eventData![IdentityConstants.EventDataKeys.VISITOR_ID_ECID])
        XCTAssertEqual("", eventData![IdentityConstants.EventDataKeys.ADVERTISING_IDENTIFIER] as? String)
        XCTAssertNil(eventData![IdentityConstants.EventDataKeys.VISITOR_IDS_LIST])
        XCTAssertFalse(mockHitQueue.queuedHits.isEmpty) // hit should be queued in the hit queue
        let hit = try! JSONDecoder().decode(IdentityHit.self, from: mockHitQueue.queuedHits.first!.data!)
        XCTAssertTrue(hit.url.absoluteString.contains("device_consent=0")) // device flag should be added
    }

    /// When we currently have a valid ad id and update to an empty ad id we should sync with the device consent flag set to 0
    func testSyncIdentifiersAdIDIsUpdatedFromValidToEmptyFirstSync() {
        // setup
        let configSharedState = [IdentityConstants.Configuration.EXPERIENCE_CLOUD_ORGID: "test-org",
                                 IdentityConstants.Configuration.EXPERIENCE_CLOUD_SERVER: "test-server",
                                 IdentityConstants.Configuration.GLOBAL_CONFIG_PRIVACY: PrivacyStatus.optedIn.rawValue] as [String: Any]
        var props = IdentityProperties()
        props.advertisingIdentifier = "test-ad-id"
        props.ecid = ECID()
        props.lastSync = Date()
        state = IdentityState(identityProperties: props, hitQueue: MockHitQueue(processor: MockHitProcessor()), pushIdManager: mockPushIdManager)
        state.lastValidConfig = configSharedState

        // test
        let data = [IdentityConstants.EventDataKeys.ADVERTISING_IDENTIFIER: ""]
        let event = Event(name: "Fake Sync Event", type: EventType.genericIdentity, source: EventSource.requestReset, data: data)
        let eventData = state.syncIdentifiers(event: event)

        // verify
        XCTAssertEqual(3, eventData!.count)
        XCTAssertNotNil(eventData![IdentityConstants.EventDataKeys.VISITOR_ID_ECID])
        XCTAssertEqual("", eventData![IdentityConstants.EventDataKeys.ADVERTISING_IDENTIFIER] as? String)
        XCTAssertNil(eventData![IdentityConstants.EventDataKeys.VISITOR_IDS_LIST])
        XCTAssertFalse(mockHitQueue.queuedHits.isEmpty) // hit should be queued in the hit queue
        let hit = try! JSONDecoder().decode(IdentityHit.self, from: mockHitQueue.queuedHits.first!.data!)
        XCTAssertTrue(hit.url.absoluteString.contains("device_consent=0")) // device flag should be added
    }

    /// Tests that when updating the ad id from zero string to valid we add the consent flag as true
    func testSyncIdentifiersAdIDIsUpdatedFromZeroStringToValid() {
        // setup
        let configSharedState = [IdentityConstants.Configuration.EXPERIENCE_CLOUD_ORGID: "test-org",
                                 IdentityConstants.Configuration.EXPERIENCE_CLOUD_SERVER: "test-server",
                                 IdentityConstants.Configuration.GLOBAL_CONFIG_PRIVACY: PrivacyStatus.optedIn.rawValue] as [String: Any]
        var props = IdentityProperties()
        props.advertisingIdentifier = IdentityConstants.Default.ZERO_ADVERTISING_ID
        state = IdentityState(identityProperties: props, hitQueue: MockHitQueue(processor: MockHitProcessor()), pushIdManager: mockPushIdManager)
        state.lastValidConfig = configSharedState

        // test
        let eventData = state.syncIdentifiers(event: Event.fakeAdIDEvent())

        // verify
        XCTAssertEqual(3, eventData!.count)
        XCTAssertNotNil(eventData![IdentityConstants.EventDataKeys.VISITOR_ID_ECID])
        XCTAssertEqual("test-ad-id", eventData![IdentityConstants.EventDataKeys.ADVERTISING_IDENTIFIER] as? String)
        let idList = eventData![IdentityConstants.EventDataKeys.VISITOR_IDS_LIST] as? [[String: Any]]
        XCTAssertEqual(1, idList?.count)
        let customId = idList?.first!
        XCTAssertEqual("test-ad-id", customId?[CustomIdentity.CodingKeys.identifier.rawValue] as? String)
        XCTAssertEqual("d_cid_ic", customId?[CustomIdentity.CodingKeys.origin.rawValue] as? String)
        XCTAssertEqual("DSID_20915", customId?[CustomIdentity.CodingKeys.type.rawValue] as? String)
        XCTAssertFalse(mockHitQueue.queuedHits.isEmpty) // hit should be queued in the hit queue
        let hit = try! JSONDecoder().decode(IdentityHit.self, from: mockHitQueue.queuedHits.first!.data!)
        XCTAssertTrue(hit.url.absoluteString.contains("device_consent=1")) // device flag should be added
    }

    /// Tests that the location hint and blob are present int he event data
    func testSyncIdentifiersAppendsBlobAndLocationHint() {
        // setup
        let configSharedState = [IdentityConstants.Configuration.EXPERIENCE_CLOUD_ORGID: "test-org",
                                 IdentityConstants.Configuration.EXPERIENCE_CLOUD_SERVER: "test-server",
                                 IdentityConstants.Configuration.GLOBAL_CONFIG_PRIVACY: PrivacyStatus.optedIn.rawValue] as [String: Any]
        var props = IdentityProperties()
        props.locationHint = "locHinty"
        props.blob = "blobby"
        state = IdentityState(identityProperties: props, hitQueue: MockHitQueue(processor: MockHitProcessor()), pushIdManager: mockPushIdManager)
        state.lastValidConfig = configSharedState

        // test
        let eventData = state.syncIdentifiers(event: Event.fakePushIDEvent())

        // verify
        XCTAssertEqual(4, eventData!.count)
        XCTAssertNotNil(eventData![IdentityConstants.EventDataKeys.VISITOR_ID_ECID])
        XCTAssertEqual(props.locationHint, eventData![IdentityConstants.EventDataKeys.VISITOR_ID_LOCATION_HINT] as? String)
        XCTAssertEqual(props.blob, eventData![IdentityConstants.EventDataKeys.VISITOR_ID_BLOB] as? String)
        XCTAssertEqual("test-push-id", eventData![IdentityConstants.EventDataKeys.PUSH_IDENTIFIER] as? String)
        XCTAssertFalse(mockHitQueue.queuedHits.isEmpty) // hit should be queued in the hit queue
    }

    /// Tests that a hit is not queued for is sync event
    func testSyncIdentifiersDoesNotQueue() {
        // setup
        let configSharedState = [IdentityConstants.Configuration.EXPERIENCE_CLOUD_ORGID: "test-org",
                                 IdentityConstants.Configuration.EXPERIENCE_CLOUD_SERVER: "test-server",
                                 IdentityConstants.Configuration.GLOBAL_CONFIG_PRIVACY: PrivacyStatus.optedIn.rawValue] as [String: Any]
        var props = IdentityProperties()
        props.ecid = ECID() // visitor ID is null initially and set for the first time in
        // shouldSync(). Mimic a second call to shouldSync by setting the ecid
        props.lastSync = Date() // set last sync to now
        state = IdentityState(identityProperties: props, hitQueue: MockHitQueue(processor: MockHitProcessor()), pushIdManager: mockPushIdManager)
        state.lastValidConfig = configSharedState

        // test
        let data = [IdentityConstants.EventDataKeys.IS_SYNC_EVENT: true] as [String: Any]
        _ = state.syncIdentifiers(event: Event(name: "ID Sync Test Event", type: EventType.identity, source: EventSource.requestIdentity, data: data))

        // verify
        XCTAssertTrue(mockHitQueue.queuedHits.isEmpty) // hit should NOT be queued in the hit queue
    }

    func testSyncIdentifiersWhenPrivacyIsOptIn() {
        // setup
        state.lastValidConfig = [IdentityConstants.Configuration.EXPERIENCE_CLOUD_ORGID: "latestOrg", IdentityConstants.Configuration.GLOBAL_CONFIG_PRIVACY: PrivacyStatus.optedIn.rawValue] as [String: Any]

        // test
        let eventData = state.syncIdentifiers(event: Event.fakeSyncIDEvent())

        // verify
        XCTAssertNotNil(eventData)
    }

    /// We are ready to process the event when the config shared state has an opt-in privacy status but our previous config has an opt-out
    func testSyncIdentifiersReturnNilWhenLatestPrivacyIsOptOut() {
        // setup
        state.lastValidConfig = [IdentityConstants.Configuration.EXPERIENCE_CLOUD_ORGID: "latestOrg", IdentityConstants.Configuration.GLOBAL_CONFIG_PRIVACY: PrivacyStatus.optedOut.rawValue] as [String: Any]

        // test
        let eventData = state.syncIdentifiers(event: Event.fakeSyncIDEvent())

        // verify
        XCTAssertNil(eventData)
    }

    // MARK: readyForSyncIdentifiers(...)

    /// When no valid configuration is available we should return false to wait for a valid configuration
    func testReadyForSyncIdentifiersNoValidConfig() {
        // test
        let readyForSync = state.readyForSyncIdentifiers(event: Event.fakeSyncIDEvent(), configurationSharedState: [:])

        // verify
        XCTAssertFalse(readyForSync)
    }

    func testReadyForSyncIdentifiersShouldSyncWithEmptyCurrentConfigButValidLatestConfig() {
        // setup
        state.lastValidConfig = [IdentityConstants.Configuration.EXPERIENCE_CLOUD_ORGID: "latestOrg", IdentityConstants.Configuration.GLOBAL_CONFIG_PRIVACY: PrivacyStatus.optedIn.rawValue] as [String: Any]

        // test
        let readyForSync = state.readyForSyncIdentifiers(event: Event.fakeSyncIDEvent(), configurationSharedState: [:])

        // verify
        XCTAssertTrue(readyForSync)
    }

    func testReadyForSyncIdentifiersShouldNotSyncWithEmptyCurrentConfigAndNilLatestConfig() {
        // setup
        let configSharedState = [IdentityConstants.Configuration.EXPERIENCE_CLOUD_ORGID: ""] as [String: Any]

        // test
        let readyForSync = state.readyForSyncIdentifiers(event: Event.fakeSyncIDEvent(), configurationSharedState: configSharedState)

        // verify
        XCTAssertFalse(readyForSync)
    }

    // MARK: handleHitResponse(...) tests

    /// Tests that when a non-opt out response is handled that we update the last sync and other identity properties, along with dispatching two identity events
    func testHandleHitResponseHappy() {
        // setup
        let dispatchedEventExpectation = XCTestExpectation(description: "Two events should be dispatched")
        dispatchedEventExpectation.expectedFulfillmentCount = 2 // 2 identity events
        dispatchedEventExpectation.assertForOverFulfill = true
        let sharedStateExpectation = XCTestExpectation(description: "Shared state should be updated since the blob/hint are updated.")
        sharedStateExpectation.assertForOverFulfill = true

        var props = IdentityProperties()
        props.lastSync = Date()
        props.privacyStatus = .optedIn
        let hit = IdentityHit.fakeHit()
        let hitResponse = IdentityHitResponse.fakeHitResponse(error: nil, optOutList: nil)

        state = IdentityState(identityProperties: props, hitQueue: MockHitQueue(processor: MockHitProcessor()), pushIdManager: mockPushIdManager)

        // test
        state.handleHitResponse(hit: hit, response: try! JSONEncoder().encode(hitResponse), eventDispatcher: { event in
            XCTAssertEqual(state.identityProperties.toEventData().count, event.data?.count) // event should contain the identity properties in the event data
            dispatchedEventExpectation.fulfill()
        }) { _, _ in
            sharedStateExpectation.fulfill()
        }

        // verify
        wait(for: [dispatchedEventExpectation], timeout: 1)
        XCTAssertNotEqual(props.lastSync, state.identityProperties.lastSync) // sync should be updated regardless of response
        XCTAssertEqual(hitResponse.blob, state.identityProperties.blob) // blob should have been updated
        XCTAssertEqual("\(String(describing: hitResponse.hint!))", state.identityProperties.locationHint) // locationHint should have been updated
        XCTAssertEqual(hitResponse.ttl, state.identityProperties.ttl) // ttl should have been updated
    }

    /// When the opt-out list in the response is not empty that we dispatch a configuration event setting the privacy to opt out
    func testHandleHitResponseOptOutList() {
        // setup
        let dispatchedEventExpectation = XCTestExpectation(description: "Three events should be dispatched")
        dispatchedEventExpectation.expectedFulfillmentCount = 3 // 2 identity events, 1 configuration
        dispatchedEventExpectation.assertForOverFulfill = true
        let sharedStateExpectation = XCTestExpectation(description: "Shared state should not be updated")
        sharedStateExpectation.isInverted = true

        var props = IdentityProperties()
        props.lastSync = Date()
        props.privacyStatus = .optedIn
        let hit = IdentityHit.fakeHit()
        let hitResponse = IdentityHitResponse.fakeHitResponse(error: nil, optOutList: ["optOut"])

        state = IdentityState(identityProperties: props, hitQueue: MockHitQueue(processor: MockHitProcessor()), pushIdManager: mockPushIdManager)

        // test
        state.handleHitResponse(hit: hit, response: try! JSONEncoder().encode(hitResponse), eventDispatcher: { _ in
            dispatchedEventExpectation.fulfill()
        }) { _, _ in
            sharedStateExpectation.fulfill()
        }

        // verify
        wait(for: [dispatchedEventExpectation], timeout: 1)
        XCTAssertNotEqual(props.lastSync, state.identityProperties.lastSync) // sync should be updated regardless of response
        XCTAssertEqual(hitResponse.blob, state.identityProperties.blob) // blob should have been updated
        XCTAssertEqual("\(String(describing: hitResponse.hint!))", state.identityProperties.locationHint) // locationHint should have been updated
        XCTAssertEqual(hitResponse.ttl, state.identityProperties.ttl) // ttl should have been updated
    }

    /// Tests that when the hit response indicates an error that we do not update the identity properties
    func testHandleHitResponseError() {
        // setup
        let dispatchedEventExpectation = XCTestExpectation(description: "Two events should be dispatched")
        dispatchedEventExpectation.expectedFulfillmentCount = 2 // 2 identity events
        dispatchedEventExpectation.assertForOverFulfill = true
        let sharedStateExpectation = XCTestExpectation(description: "Shared state should not be updated")
        sharedStateExpectation.isInverted = true

        var props = IdentityProperties()
        props.lastSync = Date()
        props.privacyStatus = .optedIn
        let hit = IdentityHit.fakeHit()
        let hitResponse = IdentityHitResponse.fakeHitResponse(error: "err message", optOutList: nil)

        state = IdentityState(identityProperties: props, hitQueue: MockHitQueue(processor: MockHitProcessor()), pushIdManager: mockPushIdManager)

        // test
        state.handleHitResponse(hit: hit, response: try! JSONEncoder().encode(hitResponse), eventDispatcher: { _ in
            dispatchedEventExpectation.fulfill()
        }) { _, _ in
            sharedStateExpectation.fulfill()
        }

        // verify
        wait(for: [dispatchedEventExpectation], timeout: 1)
        XCTAssertNotEqual(props.lastSync, state.identityProperties.lastSync) // sync should be updated regardless of response
        XCTAssertNotEqual(hitResponse.blob, state.identityProperties.blob) // blob should not have been updated
        XCTAssertNotEqual(hitResponse.hint, Int(state.identityProperties.locationHint ?? "-1")) // locationHint should not have been updated
        XCTAssertNotEqual(hitResponse.ttl, state.identityProperties.ttl) // ttl should not have been updated
    }

    /// Tests that when we are opted out that we do not update the identity properties
    func testHandleHitResponseOptOut() {
        // setup
        let dispatchedEventExpectation = XCTestExpectation(description: "Two events should be dispatched")
        dispatchedEventExpectation.expectedFulfillmentCount = 2 // 2 identity events
        dispatchedEventExpectation.assertForOverFulfill = true
        let sharedStateExpectation = XCTestExpectation(description: "Shared state should not be updated as we are opted-out")
        sharedStateExpectation.isInverted = true

        var props = IdentityProperties()
        props.lastSync = Date()
        props.privacyStatus = .optedOut
        let hit = IdentityHit.fakeHit()
        let hitResponse = IdentityHitResponse.fakeHitResponse(error: nil, optOutList: ["optOut"])

        state = IdentityState(identityProperties: props, hitQueue: MockHitQueue(processor: MockHitProcessor()), pushIdManager: mockPushIdManager)

        // test
        state.handleHitResponse(hit: hit, response: try! JSONEncoder().encode(hitResponse), eventDispatcher: { _ in
            dispatchedEventExpectation.fulfill()
        }) { _, _ in
            sharedStateExpectation.fulfill()
        }

        // verify
        wait(for: [dispatchedEventExpectation], timeout: 1)
        XCTAssertNotEqual(props.lastSync, state.identityProperties.lastSync) // sync should be updated regardless of response
        XCTAssertNotEqual(hitResponse.blob, state.identityProperties.blob) // blob should not have been updated
        XCTAssertNotEqual(hitResponse.hint, Int(state.identityProperties.locationHint ?? "-1")) // locationHint should not have been updated
        XCTAssertNotEqual(hitResponse.ttl, state.identityProperties.ttl) // ttl should not have been updated
    }

    /// Tests that when we get nil data back that we only dispatch one event and do not update the properties
    func testHandleHitResponseNilData() {
        // setup
        let dispatchedEventExpectation = XCTestExpectation(description: "One event should be dispatched")
        dispatchedEventExpectation.assertForOverFulfill = true
        dispatchedEventExpectation.expectedFulfillmentCount = 2
        let sharedStateExpectation = XCTestExpectation(description: "Shared state should not be updated as the response was empty")
        sharedStateExpectation.isInverted = true

        var props = IdentityProperties()
        props.lastSync = Date()
        props.privacyStatus = .optedOut

        state = IdentityState(identityProperties: props, hitQueue: MockHitQueue(processor: MockHitProcessor()), pushIdManager: mockPushIdManager)

        // test
        state.handleHitResponse(hit: IdentityHit.fakeHit(), response: nil, eventDispatcher: { _ in
            dispatchedEventExpectation.fulfill()
        }) { _, _ in
            sharedStateExpectation.fulfill()
        }

        // verify
        wait(for: [dispatchedEventExpectation], timeout: 1)
        XCTAssertNotEqual(props.lastSync, state.identityProperties.lastSync) // sync should be updated regardless of response
    }

    // MARK: processPrivacyChange(...)

    /// Tests that when the event data is empty that we do not update shared state or the push identifier
    func testProcessPrivacyChangeNoPrivacyInEventData() {
        // setup
        var props = IdentityProperties()
        props.privacyStatus = .unknown
        props.ecid = ECID()

        state = IdentityState(identityProperties: props, hitQueue: MockHitQueue(processor: MockHitProcessor()), pushIdManager: mockPushIdManager)
        let event = Event(name: "Test event", type: EventType.identity, source: EventSource.requestIdentity, data: nil)

        // test
        state.processPrivacyChange(event: event, createSharedState: { (data, event) in
            XCTFail("Shared state should not be updated")
        })

        // verify
        XCTAssertTrue(mockDataStore.dict.isEmpty) // identity properties should have not been saved to persistence
        XCTAssertFalse(mockPushIdManager.calledUpdatePushId)
        XCTAssertTrue(!mockHitQueue.calledBeginProcessing && !mockHitQueue.calledSuspend && !mockHitQueue.calledClear) // should not notify the hit queue of the privacy change
        XCTAssertEqual(PrivacyStatus.unknown, state.identityProperties.privacyStatus) // privacy status should not change
    }

    /// Tests that when we get an opt-in privacy status that we update the privacy status and start the hit queue
    func testProcessPrivacyChangeToOptIn() {
        // setup
        var props = IdentityProperties()
        props.privacyStatus = .unknown
        props.ecid = ECID()

        state = IdentityState(identityProperties: props, hitQueue: MockHitQueue(processor: MockHitProcessor()), pushIdManager: mockPushIdManager)
        let event = Event(name: "Test event", type: EventType.identity, source: EventSource.requestIdentity, data: [IdentityConstants.Configuration.GLOBAL_CONFIG_PRIVACY: PrivacyStatus.optedIn.rawValue])

        // test
        state.processPrivacyChange(event: event, createSharedState: { (_, _) in
            XCTFail("Shared state should not be updated")
        })

        // verify
        XCTAssertFalse(mockPushIdManager.calledUpdatePushId)
        XCTAssertTrue(mockDataStore.dict.isEmpty) // identity properties should have not been saved to persistence
        XCTAssertTrue(mockHitQueue.calledBeginProcessing) // we should start the hit queue
        XCTAssertEqual(PrivacyStatus.optedIn, state.identityProperties.privacyStatus) // privacy status should change to opt in
    }

    /// Tests that when we update privacy to opt-out that we suspend the hit queue and share state
    func testProcessPrivacyChangeToOptOut() {
        // setup
        let sharedStateExpectation = XCTestExpectation(description: "Shared state should be updated once")
        var props = IdentityProperties()
        props.privacyStatus = .unknown
        props.ecid = ECID()

        state = IdentityState(identityProperties: props, hitQueue: MockHitQueue(processor: MockHitProcessor()), pushIdManager: mockPushIdManager)
        let event = Event(name: "Test event", type: EventType.identity, source: EventSource.requestIdentity, data: [IdentityConstants.Configuration.GLOBAL_CONFIG_PRIVACY: PrivacyStatus.optedOut.rawValue])

        // test
        state.processPrivacyChange(event: event, createSharedState: { (data, event) in
            sharedStateExpectation.fulfill()
        })

        // verify
        wait(for: [sharedStateExpectation], timeout: 1)
        XCTAssertFalse(mockDataStore.dict.isEmpty) // identity properties should have been saved to persistence
        XCTAssertTrue(mockPushIdManager.calledUpdatePushId)
        XCTAssertTrue(mockHitQueue.calledSuspend && mockHitQueue.calledClear) // we should suspend the queue and clear it
        XCTAssertEqual(PrivacyStatus.optedOut, state.identityProperties.privacyStatus) // privacy status should change to opt out
    }

    /// Tests that when we got from opt out to opt in that we dispatch a force sync event
    func testProcessPrivacyChangeFromOptOutToOptIn() {
        // setup
        let sharedStateExpectation = XCTestExpectation(description: "Shared state should be updated once")
        var props = IdentityProperties()
        props.privacyStatus = .optedOut

        state = IdentityState(identityProperties: props, hitQueue: MockHitQueue(processor: MockHitProcessor()), pushIdManager: mockPushIdManager)
        let configSharedState = [IdentityConstants.Configuration.EXPERIENCE_CLOUD_ORGID: "test-org",
                                 IdentityConstants.Configuration.EXPERIENCE_CLOUD_SERVER: "test-server",
                                 IdentityConstants.Configuration.GLOBAL_CONFIG_PRIVACY: PrivacyStatus.optedIn.rawValue] as [String: Any]
        state.lastValidConfig = configSharedState
        let event = Event(name: "Test event", type: EventType.identity, source: EventSource.requestIdentity, data: [IdentityConstants.Configuration.GLOBAL_CONFIG_PRIVACY: PrivacyStatus.optedIn.rawValue])

        // test
        state.processPrivacyChange(event: event, createSharedState: { (_, _) in
            sharedStateExpectation.fulfill()
        })

        // verify
        wait(for: [sharedStateExpectation], timeout: 1)
        XCTAssertFalse(mockDataStore.dict.isEmpty) // identity properties should have been saved to persistence
        XCTAssertTrue(mockHitQueue.calledBeginProcessing) // we should start the hit queue
        XCTAssertEqual(PrivacyStatus.optedIn, state.identityProperties.privacyStatus) // privacy status should change to opt in
    }

    /// When we go from opt-out to unknown we should suspend the queue and update the privacy status
    func testProcessPrivacyChangeFromOptOutToUnknown() {
        // setup
        let sharedStateExpectation = XCTestExpectation(description: "A force sync event should be dispatched")
        var props = IdentityProperties()
        props.privacyStatus = .optedOut

        state = IdentityState(identityProperties: props, hitQueue: MockHitQueue(processor: MockHitProcessor()), pushIdManager: mockPushIdManager)
        let configSharedState = [IdentityConstants.Configuration.EXPERIENCE_CLOUD_ORGID: "test-org",
                                 IdentityConstants.Configuration.EXPERIENCE_CLOUD_SERVER: "test-server",
                                 IdentityConstants.Configuration.GLOBAL_CONFIG_PRIVACY: PrivacyStatus.optedIn.rawValue] as [String: Any]
        state.lastValidConfig = configSharedState
        let event = Event(name: "Test event", type: EventType.identity, source: EventSource.requestIdentity, data: [IdentityConstants.Configuration.GLOBAL_CONFIG_PRIVACY: PrivacyStatus.unknown.rawValue])

        // test
        state.processPrivacyChange(event: event, createSharedState: { _, _ in
            sharedStateExpectation.fulfill()
        })

        // verify
        wait(for: [sharedStateExpectation], timeout: 1)
        XCTAssertFalse(mockDataStore.dict.isEmpty) // identity properties should have been saved to persistence
        XCTAssertTrue(mockHitQueue.calledSuspend) // we should have suspended the hit queue
        XCTAssertEqual(PrivacyStatus.unknown, state.identityProperties.privacyStatus) // privacy status should change to opt in
    }
    
    // MARK: HandleAnalyticsResponse(...)
    
    /// Tests that when receives a valid analytics event and response identity event source that we dispatch an Avid Sync event
    func testHandleAnalyticsResponseHappy() {
        // setup
        let dispatchedEventExpectation = XCTestExpectation(description: "one event should be dispatched")
        dispatchedEventExpectation.expectedFulfillmentCount = 1 // 1 identity events
        dispatchedEventExpectation.assertForOverFulfill = true
        
        let eventData = [IdentityConstants.Analytics.ANALYTICS_ID: "aid" ] as [String: Any]
        
        let event = Event(name: "Test Analytics Response Event", type: EventType.analytics, source: EventSource.responseIdentity, data: eventData)

        //test
        state.handleAnalyticsResponse(event: event, eventDispatcher: { _ in
            dispatchedEventExpectation.fulfill()
        })

        // verify
        XCTAssertEqual(1,mockDataStore.dict.count) // identity properties should have been saved to persistence
    }
    
}

private extension Event {
    static func fakeSyncIDEvent() -> Event {
        let ids = ["k1": "v1", "k2": "v2"]
        let data = [IdentityConstants.EventDataKeys.IDENTIFIERS: ids, IdentityConstants.EventDataKeys.IS_SYNC_EVENT: true] as [String: Any]
        return Event(name: "Fake Sync Event", type: EventType.identity, source: EventSource.requestReset, data: data)
    }

    static func fakePushIDEvent() -> Event {
        let data = [IdentityConstants.EventDataKeys.PUSH_IDENTIFIER: "test-push-id"]
        return Event(name: "Fake Sync Event", type: EventType.genericIdentity, source: EventSource.requestReset, data: data)
    }

    static func fakeAdIDEvent() -> Event {
        let data = [IdentityConstants.EventDataKeys.ADVERTISING_IDENTIFIER: "test-ad-id"]
        return Event(name: "Fake Sync Event", type: EventType.genericIdentity, source: EventSource.requestReset, data: data)
    }
}

private extension IdentityHit {
    static func fakeHit() -> IdentityHit {
        let event = Event(name: "Hit Event", type: EventType.identity, source: EventSource.requestIdentity, data: nil)
        let hit = IdentityHit(url: URL(string: "adobe.com")!, event: event)

        return hit
    }
}

private extension IdentityHitResponse {
    static func fakeHitResponse(error: String?, optOutList: [String]?) -> IdentityHitResponse {
        return IdentityHitResponse(blob: "response-test-blob", ecid: "response-test-ecid", hint: 6, error: error, ttl: 3000, optOutList: optOutList)
    }
}
