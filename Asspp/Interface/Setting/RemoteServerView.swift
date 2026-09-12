import SwiftUI

struct RemoteServerView: View {
    @State private var address = RemoteSAPAuthenticator.baseURL?.absoluteString ?? ""
    @State private var token = (try? RemoteSAPAuthenticator.tokenKeychain.get("accessToken")) ?? ""
    @State private var message = ""

    var body: some View {
        Form {
            Section {
                TextField("https://你的服务器域名", text: $address)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                SecureField("X-Access-Token（可选）", text: $token)
                Button("保存服务器设置") { save() }
                if !message.isEmpty { Text(message) }
            } header: {
                Text("AssppWeb 登录服务器")
            } footer: {
                Text("填写你信任的 AssppWeb HTTPS 地址，不需要添加 /api/apple/authenticate。登录和刷新登录时，Apple ID、密码、验证码及会话信息会发送至该服务器。账号保存在钥匙串，IPA 通过手机网络直接从 Apple 下载。留空可恢复原生登录。")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("远端登录服务器")
    }

    private func save() {
        let value = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.isEmpty || RemoteSAPAuthenticator.validURL(value) != nil else {
            message = "请输入有效的 HTTPS 服务器地址（不含用户名、密码、查询参数）。"
            return
        }
        do {
            try RemoteSAPAuthenticator.tokenKeychain.set(token.trimmingCharacters(in: .whitespacesAndNewlines), key: "accessToken")
            UserDefaults.standard.set(value, forKey: "AssppWebBaseURL")
            UserDefaults.standard.removeObject(forKey: "AssppWebAccessToken")
            address = value
            message = "已保存，下次登录或刷新登录时生效。"
        } catch {
            message = "保存失败：\(error.localizedDescription)"
        }
    }
}
