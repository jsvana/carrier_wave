// POTA (Parks on the Air) ADIF export and upload functionality.
//
// Groups QSOs by UTC date and park reference, generating separate
// ADIF files suitable for upload to pota.app.

import Foundation
import SwiftData

// MARK: - POTAError

enum POTAError: Error, LocalizedError {
    case notAuthenticated
    case uploadFailed(String)
    case fetchFailed(String)
    case invalidParkReference
    case networkError(Error)
    case maintenanceWindow

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            "Not authenticated with POTA"
        case let .uploadFailed(reason):
            "POTA upload failed: \(reason)"
        case let .fetchFailed(reason):
            "POTA fetch failed: \(reason)"
        case .invalidParkReference:
            "Invalid park reference format"
        case let .networkError(error):
            "Network error: \(error.localizedDescription)"
        case .maintenanceWindow:
            "POTA is in maintenance (0000-0400 UTC)"
        }
    }
}

// MARK: - POTAActivationsResponse

struct POTAActivationsResponse: Decodable {
    let count: Int
    let activations: [POTARemoteActivation]
}

// MARK: - POTARemoteActivation

struct POTARemoteActivation: Decodable {
    enum CodingKeys: String, CodingKey {
        case callsign
        case date
        case reference
        case name
        case total
        case cw
        case data
        case phone
        case parktypeDesc = "parktype_desc"
        case locationDesc = "location_desc"
        case firstQso = "first_qso"
        case lastQso = "last_qso"
    }

    let callsign: String
    let date: String
    let reference: String
    let name: String?
    let parktypeDesc: String?
    let locationDesc: String?
    let firstQso: String?
    let lastQso: String?
    let total: Int
    let cw: Int
    let data: Int
    let phone: Int
}

// MARK: - POTALogbookResponse

struct POTALogbookResponse: Decodable {
    let count: Int
    let entries: [POTARemoteQSO]
}

// MARK: - POTARemoteQSO

struct POTARemoteQSO: Decodable {
    // MARK: Lifecycle

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        qsoId = try container.decode(Int64.self, forKey: .qsoId)
        qsoDateTime = try container.decode(String.self, forKey: .qsoDateTime)
        stationCallsign = try container.decode(String.self, forKey: .stationCallsign)
        operatorCallsign = try container.decodeIfPresent(String.self, forKey: .operatorCallsign)
        workedCallsign = try container.decode(String.self, forKey: .workedCallsign)
        band = try container.decodeIfPresent(String.self, forKey: .band)
        mode = try container.decodeIfPresent(String.self, forKey: .mode)
        mySig = try container.decodeIfPresent(String.self, forKey: .mySig)
        mySigInfo = try container.decodeIfPresent(String.self, forKey: .mySigInfo)
        reference = try container.decodeIfPresent(String.self, forKey: .reference)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        locationDesc = try container.decodeIfPresent(String.self, forKey: .locationDesc)
        sig = try container.decodeIfPresent(String.self, forKey: .sig)
        rstSent = Self.decodeStringOrInt(container: container, key: .rstSent)
        rstRcvd = Self.decodeStringOrInt(container: container, key: .rstRcvd)
        sigInfo = Self.decodeStringOrInt(container: container, key: .sigInfo)
        p2pMatch = Self.decodeStringOrInt(container: container, key: .p2pMatch)
    }

    // MARK: Internal

    enum CodingKeys: String, CodingKey {
        case qsoId
        case band
        case mode
        case reference
        case name
        case sig
        case qsoDateTime
        case stationCallsign = "station_callsign"
        case operatorCallsign = "operator_callsign"
        case workedCallsign = "worked_callsign"
        case rstSent = "rst_sent"
        case rstRcvd = "rst_rcvd"
        case mySig = "my_sig"
        case mySigInfo = "my_sig_info"
        case locationDesc
        case sigInfo = "sig_info"
        case p2pMatch
    }

    let qsoId: Int64
    let qsoDateTime: String
    let stationCallsign: String
    let operatorCallsign: String?
    let workedCallsign: String
    let band: String?
    let mode: String?
    let rstSent: String?
    let rstRcvd: String?
    let mySig: String?
    let mySigInfo: String?
    let reference: String?
    let name: String?
    let locationDesc: String?
    let sig: String?
    let sigInfo: String?
    let p2pMatch: String?

    // MARK: Private

    private static func decodeStringOrInt(
        container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys
    ) -> String? {
        if let value = try? container.decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        return nil
    }
}

// MARK: - POTAFetchedQSO

struct POTAFetchedQSO {
    let callsign: String
    let band: String
    let mode: String
    let timestamp: Date
    let rstSent: String?
    let rstReceived: String?
    let myCallsign: String
    let parkReference: String?
    let myState: String?
    let potaQsoId: Int64
}

// MARK: - POTAUploadResult

struct POTAUploadResult {
    let success: Bool
    let qsosAccepted: Int
    let message: String?
}

// MARK: - POTAClient

actor POTAClient {
    // MARK: Lifecycle

    init(authService: POTAAuthService) {
        self.authService = authService
    }

    // MARK: Internal

    let baseURL = "https://api.pota.app"
    let authService: POTAAuthService

    // Maintenance window methods in POTAClient+Maintenance.swift

    /// Get all unique park references from QSOs (excludes nil and empty)
    static func groupQSOsByPark(_ qsos: [QSO]) -> [String: [QSO]] {
        Dictionary(grouping: qsos.filter { $0.parkReference?.isEmpty == false }) {
            $0.parkReference!
        }
    }

    func uploadActivation(parkReference: String, qsos: [QSO]) async throws -> POTAUploadResult {
        let debugLog = await SyncDebugLog.shared

        guard validateParkReference(parkReference) else {
            await debugLog.error(
                "Invalid park reference format: '\(parkReference)' (expected format like K-1234)",
                service: .pota
            )
            throw POTAError.invalidParkReference
        }

        let normalizedParkRef = parkReference.uppercased()
        let token = try await authService.ensureValidToken()

        let parkQSOs = qsos.filter { $0.parkReference?.uppercased() == normalizedParkRef }
        guard !parkQSOs.isEmpty else {
            await debugLog.info("No QSOs to upload for park \(normalizedParkRef)", service: .pota)
            return POTAUploadResult(
                success: true, qsosAccepted: 0, message: "No QSOs for this park"
            )
        }

        guard
            let requestData = await buildUploadRequest(
                parkReference: normalizedParkRef, qsos: qsos, token: token
            )
        else {
            throw POTAError.uploadFailed("Failed to build request")
        }

        await debugLog.info(
            "Uploading \(parkQSOs.count) QSOs to park \(normalizedParkRef)", service: .pota
        )
        await debugLog.debug(
            "POST /adif - location=\(requestData.location), ref=\(normalizedParkRef), file=\(requestData.filename)",
            service: .pota
        )

        let (data, response) = try await URLSession.shared.data(for: requestData.request)

        guard let httpResponse = response as? HTTPURLResponse else {
            await debugLog.error("Invalid response (not HTTP)", service: .pota)
            throw POTAError.uploadFailed("Invalid response")
        }

        return try await handleUploadResponse(
            data: data, httpResponse: httpResponse,
            parkReference: normalizedParkRef, qsoCount: parkQSOs.count
        )
    }

    /// Upload activation with attempt recording for debugging
    func uploadActivationWithRecording(
        parkReference: String, qsos: [QSO], modelContext: ModelContext
    ) async throws -> POTAUploadResult {
        let debugLog = await SyncDebugLog.shared
        let startTime = Date()

        guard validateParkReference(parkReference) else {
            await debugLog.error(
                "Invalid park reference format: '\(parkReference)' (expected format like K-1234)",
                service: .pota
            )
            throw POTAError.invalidParkReference
        }

        let normalizedParkRef = parkReference.uppercased()
        let token = try await authService.ensureValidToken()

        let parkQSOs = qsos.filter { $0.parkReference?.uppercased() == normalizedParkRef }
        guard !parkQSOs.isEmpty else {
            await debugLog.info("No QSOs to upload for park \(normalizedParkRef)", service: .pota)
            return POTAUploadResult(
                success: true, qsosAccepted: 0, message: "No QSOs for this park"
            )
        }

        guard
            let requestData = await buildUploadRequest(
                parkReference: normalizedParkRef, qsos: qsos, token: token
            )
        else {
            throw POTAError.uploadFailed("Failed to build request")
        }

        let attempt = await createUploadAttempt(
            startTime: startTime, parkReference: normalizedParkRef,
            requestData: requestData, modelContext: modelContext
        )

        await debugLog.info(
            "Uploading \(requestData.qsoCount) QSOs to park \(normalizedParkRef)", service: .pota
        )
        await debugLog.debug(
            "POST /adif - location=\(requestData.location), ref=\(normalizedParkRef), file=\(requestData.filename)",
            service: .pota
        )

        return try await executeUploadWithRecording(
            request: requestData.request, attempt: attempt, startTime: startTime,
            parkReference: normalizedParkRef, qsoCount: requestData.qsoCount
        )
    }

    // MARK: - Download Methods

    func fetchActivations() async throws -> [POTARemoteActivation] {
        let token = try await authService.ensureValidToken()

        guard let url = URL(string: "\(baseURL)/user/activations?all=1") else {
            throw POTAError.fetchFailed("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.setValue(token, forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw POTAError.fetchFailed("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw POTAError.notAuthenticated
            }
            let body = String(data: data, encoding: .utf8) ?? ""
            throw POTAError.fetchFailed("HTTP \(httpResponse.statusCode): \(body)")
        }

        let decoded = try JSONDecoder().decode(POTAActivationsResponse.self, from: data)
        return decoded.activations
    }

    func fetchActivationQSOs(
        reference: String, date: String, page: Int = 1, pageSize: Int = 100
    ) async throws -> POTALogbookResponse {
        let token = try await authService.ensureValidToken()

        var components = URLComponents(string: "\(baseURL)/user/logbook")!
        components.queryItems = [
            URLQueryItem(name: "activatorOnly", value: "1"),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "size", value: String(pageSize)),
            URLQueryItem(name: "startDate", value: date),
            URLQueryItem(name: "endDate", value: date),
            URLQueryItem(name: "reference", value: reference),
        ]

        guard let url = components.url else {
            throw POTAError.fetchFailed("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.setValue(token, forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw POTAError.fetchFailed("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw POTAError.notAuthenticated
            }
            let body = String(data: data, encoding: .utf8) ?? ""
            throw POTAError.fetchFailed("HTTP \(httpResponse.statusCode): \(body)")
        }

        return try JSONDecoder().decode(POTALogbookResponse.self, from: data)
    }

    func fetchAllActivationQSOs(reference: String, date: String) async throws -> [POTARemoteQSO] {
        var allQSOs: [POTARemoteQSO] = []
        var page = 1
        let pageSize = 100

        while true {
            let response = try await fetchActivationQSOs(
                reference: reference, date: date, page: page, pageSize: pageSize
            )
            allQSOs.append(contentsOf: response.entries)
            if response.entries.count < pageSize || page >= 10 {
                break
            }
            page += 1
        }

        return allQSOs
    }

    func fetchAllQSOs() async throws -> [POTAFetchedQSO] {
        let activations = try await fetchActivations()
        var allFetched: [POTAFetchedQSO] = []

        for activation in activations {
            let qsos = try await fetchAllActivationQSOs(
                reference: activation.reference, date: activation.date
            )
            for qso in qsos {
                if let fetched = convertToFetchedQSO(qso, activation: activation) {
                    allFetched.append(fetched)
                }
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        return allFetched
    }

    // MARK: - Job Status Methods

    func fetchJobs() async throws -> [POTAJob] {
        let debugLog = await SyncDebugLog.shared
        let token = try await authService.ensureValidToken()

        guard let url = URL(string: "\(baseURL)/user/jobs") else {
            await debugLog.error("Invalid URL for POTA jobs", service: .pota)
            throw POTAError.fetchFailed("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.setValue(token, forHTTPHeaderField: "Authorization")

        await debugLog.debug("GET /user/jobs", service: .pota)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            await debugLog.error("Invalid response (not HTTP)", service: .pota)
            throw POTAError.fetchFailed("Invalid response")
        }

        await debugLog.debug("Jobs response: \(httpResponse.statusCode)", service: .pota)

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw POTAError.notAuthenticated
            }
            let body = String(data: data, encoding: .utf8) ?? ""
            await debugLog.error(
                "Jobs fetch failed: \(httpResponse.statusCode) - \(body)", service: .pota
            )
            throw POTAError.fetchFailed("HTTP \(httpResponse.statusCode): \(body)")
        }

        let jobs = try JSONDecoder().decode([POTAJob].self, from: data)
        await debugLog.info("Fetched \(jobs.count) POTA jobs", service: .pota)
        return jobs
    }

    // MARK: Private

    private func convertToFetchedQSO(
        _ qso: POTARemoteQSO, activation: POTARemoteActivation
    ) -> POTAFetchedQSO? {
        guard let band = qso.band, let mode = qso.mode else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let timestamp = formatter.date(from: qso.qsoDateTime) ?? Date()

        let myState = activation.locationDesc?.split(separator: "-").last.map(String.init)

        return POTAFetchedQSO(
            callsign: qso.workedCallsign, band: band, mode: mode, timestamp: timestamp,
            rstSent: qso.rstSent, rstReceived: qso.rstRcvd,
            myCallsign: qso.stationCallsign, parkReference: activation.reference,
            myState: myState, potaQsoId: qso.qsoId
        )
    }
}

// Grid lookup in POTAClient+GridLookup.swift
// ADIF generation in POTAClient+ADIF.swift
// Upload helpers in POTAClient+Upload.swift
