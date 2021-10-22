import Foundation

#if !os(watchOS)
import WebKit
#endif


enum NightscoutError: LocalizedError {
    case noConnection
    case jsonDecoding

    var errorDescription: String? {
        switch self {
        case .noConnection: return "no connection"
        case .jsonDecoding: return "JSON decoding"
        }
    }
}


class Nightscout: NSObject, Logging {

    var main: MainDelegate!

#if !os(watchOS)
    var webView: WKWebView?
#endif


    init(main: MainDelegate) {
        self.main = main
    }


    // https://github.com/ps2/rileylink_ios/blob/master/NightscoutUploadKit/NightscoutUploader.swift
    // https://github.com/JohanDegraeve/xdripswift/blob/master/xdrip/Managers/NightScout/NightScoutUploadManager.swift


    // TODO: use URLQueryItems paramaters
    func request(_ endpoint: String = "", _ query: String = "", handler: @escaping (Data?, URLResponse?, Error?, [Any]) -> Void) {
        var url = "https://\(main.settings.nightscoutSite)"

        if !endpoint.isEmpty { url += ("/" + endpoint) }
        if !query.isEmpty    { url += ("?" + query) }

        var request = URLRequest(url: URL(string: url)!)
        debugLog("Nightscout: URL request: \(request.url!.absoluteString)")
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        URLSession.shared.dataTask(with: request) { [self] data, response, error in
            if let data = data {
                debugLog("Nightscout: response: \(data.string)")
                if let json = try? JSONSerialization.jsonObject(with: data) {
                    if let array = json as? [Any] {
                        DispatchQueue.main.async {
                            handler(data, response, error, array)
                        }
                    }
                }
            }
        }.resume()
    }


    func request(_ endpoint: String = "", _ query: String = "") async throws -> (Any, URLResponse) {
        var url = await "https://\(main.settings.nightscoutSite)" // FIXME: "no async operations occur" warning

        if !endpoint.isEmpty { url += ("/" + endpoint) }
        if !query.isEmpty    { url += ("?" + query) }

        var request = URLRequest(url: URL(string: url)!)
        debugLog("Nightscout: URL request: \(request.url!.absoluteString)")
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            debugLog("Nightscout: response: \(data.string)")
            do {
                let json = try JSONSerialization.jsonObject(with: data)
                if let array = json as? [Any] {
                    return (array, response)
                }
            } catch {
                log("Nightscout: error while decoding response: \(error.localizedDescription)")
                throw NightscoutError.jsonDecoding
            }
        } catch {
            log("Nightscout: server error: \(error.localizedDescription)")
            throw NightscoutError.noConnection
        }
        return (["": ""], URLResponse())
    }


    func read(handler: (([Glucose]) -> Void)? = nil) {
        request("api/v1/entries.json", "count=100") { data, response, error, array in
            var values = [Glucose]()
            for item in array {
                if let dict = item as? [String: Any] {
                    // watchOS doesn't recognize dict["date"] as Int
                    if let value = dict["sgv"] as? Int, let id = dict["date"] as? NSNumber, let device = dict["device"] as? String {
                        values.append(Glucose(value, id: Int(truncating: id), date: Date(timeIntervalSince1970: Double(truncating: id)/1000), source: device))
                    }
                }
            }
            DispatchQueue.main.async {
                self.main.history.nightscoutValues = values
                handler?(values)
            }
        }
    }

    func read() async throws -> ([Glucose], URLResponse) {
        let (data, response) = try await request("api/v1/entries.json", "count=100")
        var values = [Glucose]()
        if let array = data as? [[String: Any]?] {
            for dict in array {
                // watchOS doesn't recognize dict["date"] as Int
                if let value = dict?["sgv"] as? Int, let id = dict?["date"] as? NSNumber, let device = dict?["device"] as? String {
                    values.append(Glucose(value, id: Int(truncating: id), date: Date(timeIntervalSince1970: Double(truncating: id)/1000), source: device))
                }
            }
        }
        let glucoseArray = values
        // TODO: update from MainDelegate
        DispatchQueue.main.async {
            self.main.history.nightscoutValues = glucoseArray
        }
        return (values, response)
    }


    func post(_ endpoint: String = "", _ jsonObject: Any, handler: (((Data?, URLResponse?, Error?) -> Void))? = nil) {
        let json = try! JSONSerialization.data(withJSONObject: jsonObject, options: [])
        var request = URLRequest(url: URL(string: "https://\(main.settings.nightscoutSite)/\(endpoint)")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(main.settings.nightscoutToken.sha1, forHTTPHeaderField: "api-secret")
        URLSession.shared.uploadTask(with: request, from: json) { [self] data, response, error in
            if let error = error {
                log("Nightscout: error: \(error.localizedDescription)")
            }
            if let response = response as? HTTPURLResponse {
                let status = response.statusCode
                if status == 401 {
                    log("Nightscout: POST not authorized")
                }
                if let data = data {
                    debugLog("Nightscout: post \((200..<300).contains(status) ? "success" : "error") (\(status)): \(data.string)")
                }
            }
            DispatchQueue.main.async {
                handler?(data, response, error)
            }
        }.resume()
    }


    func post(_ endpoint: String, _ jsonObject: Any) async throws -> (Any, URLResponse) {
        let url = await "https://" + main.settings.nightscoutSite // FIXME: "no async operations occur" warning
        let token = await main.settings.nightscoutToken.sha1 // FIXME: "no async operations occur" warning
        let jsonData = try? JSONSerialization.data(withJSONObject: jsonObject)
        var request = URLRequest(url: URL(string: "\(url)/\(endpoint)")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(token, forHTTPHeaderField: "api-secret")
        request.httpBody = jsonData
        do {
            debugLog("Nightscout: posting to \(request.url!.absoluteString) \(jsonData!.string)")
            let (data, response) = try await URLSession.shared.data(for: request)
            debugLog("Nightscout: response: \(data.string)")
            if let response = response as? HTTPURLResponse {
                let status = response.statusCode
                if status == 401 {
                    log("Nightscout: POST not authorized")
                } else {
                    log("Nightscout: POST \((200..<300).contains(status) ? "success" : "error") (status: \(status))")
                }
            }
            do {
                let json = try JSONSerialization.jsonObject(with: data)
                if let array = json as? [Any] {
                    return (array, response)
                }
            } catch {
                log("Nightscout: error while decoding response: \(error.localizedDescription)")
                throw NightscoutError.jsonDecoding
            }
        } catch {
            log("Nightscout: server error: \(error.localizedDescription)")
            throw NightscoutError.noConnection
        }
        return (["": ""], URLResponse())
    }


    func post(entries: [Glucose], handler: (((Data?, URLResponse?, Error?) -> Void))? = nil) {
        let dictionaryArray = entries.map { [
            "type": "sgv",
            "dateString": ISO8601DateFormatter().string(from: $0.date),
            "date": Int64(($0.date.timeIntervalSince1970 * 1000.0).rounded()),
            "sgv": $0.value,
            "device": $0.source // TODO
            // "direction": "NOT COMPUTABLE", // TODO
        ] }
        post("api/v1/entries", dictionaryArray) { data, response, error in
            DispatchQueue.main.async {
                handler?(data, response, error)
            }
        }
    }


    func post(entries: [Glucose]) async throws {
        let dictionaryArray = entries.map { [
            "type": "sgv",
            "dateString": ISO8601DateFormatter().string(from: $0.date),
            "date": Int64(($0.date.timeIntervalSince1970 * 1000.0).rounded()),
            "sgv": $0.value,
            "device": $0.source // TODO
            // "direction": "NOT COMPUTABLE", // TODO
        ] }
        let (json, response) = try await post("api/v1/entries", dictionaryArray)
        debugLog("Nightscout: received JSON: \(json), HTTP response: \(response)")
    }


    func delete(_ endpoint: String = "api/v1/entries", _ query: String = "", handler: (((Data?, URLResponse?, Error?) -> Void))? = nil) {
        var url = "https://\(main.settings.nightscoutSite)"

        if !endpoint.isEmpty { url += ("/" + endpoint) }
        if !query.isEmpty    { url += ("?" + query) }

        var request = URLRequest(url: URL(string: url)!)
        debugLog("Nightscout: DELETE request: \(request.url!.absoluteString)")
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(main.settings.nightscoutToken.sha1, forHTTPHeaderField: "api-secret")
        URLSession.shared.dataTask(with: request) { [self] data, response, error in
            if let error = error {
                log("Nightscout: error: \(error.localizedDescription)")
            }
            if let response = response as? HTTPURLResponse {
                let status = response.statusCode
                if status == 401 {
                    log("Nightscout: DELETE not authorized")
                }
                if let data = data {
                    debugLog("Nightscout: delete \((200..<300).contains(status) ? "success" : "error") (\(status)): \(data.string)")
                }
            }
            DispatchQueue.main.async {
                handler?(data, response, error)
            }
        }.resume()
    }


    // TODO:
    func test(handler: (((Data?, URLResponse?, Error?) -> Void))? = nil) {
        var request = URLRequest(url: URL(string: "https://\(main.settings.nightscoutSite)/api/v1/entries.json?token=\(main.settings.nightscoutToken)")!)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(main.settings.nightscoutToken.sha1, forHTTPHeaderField: "api-secret")
        URLSession.shared.dataTask(with: request) { [self] data, response, error in
            if let error = error {
                log("Nightscout: authorization error: \(error.localizedDescription)")
            }
            if let response = response as? HTTPURLResponse {
                let status = response.statusCode
                if status == 401 {
                    log("Nightscout: not authorized")
                }
                if let data = data {
                    debugLog("Nightscout: authorization \((200..<300).contains(status) ? "success" : "error") (\(status)): \(data.string)")
                }
            }
            DispatchQueue.main.async {
                handler?(data, response, error)
            }
        }.resume()
    }

}


#if !os(watchOS)

extension Nightscout: WKNavigationDelegate, WKUIDelegate {

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        debugLog("Nightscout: decide policy for action: \(navigationAction)")
        decisionHandler(.allow)
        debugLog("Nightscout: allowed action: \(navigationAction)")

    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        debugLog("Nightscout: decide policy for response: \(navigationResponse)")
        decisionHandler(.allow)
        debugLog("Nightscout: allowed response: \(navigationResponse)")

    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        log("Nightscout: webView did fail: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        log("Nightscout: create veb view for action: \(navigationAction)")
        //        if navigationAction.targetFrame == nil {
        webView.load(navigationAction.request)
        //        }
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        log("Nightscout: JavaScript alert panel message: \(message)")
        main.app.JavaScriptConfirmAlertMessage = message
        main.app.showingJavaScriptConfirmAlert = true
        // TODO: block web page updates
        completionHandler()
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        log("Nightscout: TODO: JavaScript confirm panel message: \(message)")
        main.app.JavaScriptConfirmAlertMessage = message
        main.app.showingJavaScriptConfirmAlert = true
        // TODO: block web page updates
        completionHandler(true)
    }
}

#endif
