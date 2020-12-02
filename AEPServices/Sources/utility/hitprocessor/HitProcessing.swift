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

import Foundation

/// A class of types who provide the functionality for processing hits
public protocol HitProcessing: class {
    /// Defines the interval at which hits should be retried if failed
    var retryInterval: TimeInterval { get }

    /// Function that is invoked with a `DataEntity` and provides functionality for processing the hit
    /// - Parameters:
    ///   - entity: The `DataEntity` to be processed
    ///   - completion: a closure to be invoked with `true` if processing was successful and should not be retried, false if processing the hit should be retried
    func processHit(entity: DataEntity, completion: @escaping (Bool) -> Void)

    /// Determines if this hit should be queued
    /// - Parameter entity: Hit to be queued
    /// - Returns: True if the hit should be queued, false if the hit should be ignored
    func shouldQueue(entity: DataEntity) -> Bool
}
