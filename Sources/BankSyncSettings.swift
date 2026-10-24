import SwiftUI

struct BankSyncSettings: View {
    @ObservedObject var sync: BankSync
    @State private var showSetup = false
    @State private var address = "http://127.0.0.1:8787"
    @State private var key = ""
    @State private var selectedBank = ""
    @State private var confirmDisconnect = false

    var body: some View {
        MochiCard {
            VStack(alignment:.leading,spacing:16) {
                Label("Bank connections",systemImage:"building.columns").font(.headline)
                Text("Automatically import completed payments. Your bank handles sign-in; Mochi never asks for your bank password.").font(.callout).foregroundStyle(.secondary)
                if !sync.configured {
                    Text("Not connected. An Enable Banking application and a private connection service are required first.").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Link("Setup guide",destination:URL(string:"https://github.com/wuser-lab/mochi-money/blob/main/BankSyncService/README.md")!)
                        Spacer()
                        Button("Configure connection") {address = sync.serviceAddress.isEmpty ? address : sync.serviceAddress; showSetup = true}
                    }
                } else {
                    if sync.connectedBanks.isEmpty {Text("No bank accounts connected yet.").foregroundStyle(.secondary)}
                    else {Text("Connected: " + sync.connectedBanks.joined(separator:", "))}
                    HStack {
                        Picker("Bank",selection:$selectedBank) {
                            Text("Choose a bank").tag("")
                            ForEach(sync.banks) {bank in Text(bank.name).tag(bank.id)}
                        }
                        Button("Connect bank") {
                            if let bank = sync.banks.first(where:{$0.id == selectedBank}) {Task {await sync.connect(bank)}}
                        }.disabled(selectedBank.isEmpty || sync.busy)
                    }
                    DatePicker("Import payments from",selection:$sync.startDate,in:...Date(),displayedComponents:.date)
                        .help("Use a date after your last statement import to avoid overlapping historical transactions.")
                        .disabled(sync.busy)
                    Toggle("Sync automatically while Mochi Money is open",isOn:$sync.automatic)
                    Text("Checks about every six hours. Payments appear after your bank books them; this is not instant.").font(.caption).foregroundStyle(.secondary)
                    if let date = sync.lastSync {Text("Last successful sync: " + date.formatted(date:.abbreviated,time:.shortened)).font(.caption).foregroundStyle(.secondary)}
                    HStack {
                        Button("Sync now") {Task {await sync.sync()}}.disabled(sync.busy)
                        Button("Refresh banks") {Task {await sync.refresh()}}.disabled(sync.busy)
                        Spacer()
                        Button("Service settings") {address = sync.serviceAddress; showSetup = true}
                        Button("Disconnect") {confirmDisconnect = true}.disabled(sync.busy || sync.connectedBanks.isEmpty)
                    }
                }
                if sync.busy {ProgressView().controlSize(.small)}
                Text(sync.message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
        .task {await sync.refresh()}
        .sheet(isPresented:$showSetup) {
            VStack(alignment:.leading,spacing:16) {
                Text("Bank connection service").font(.title2.bold())
                Text("Enter the address and connection key of your private service. Provider keys and bank login details do not belong here.").foregroundStyle(.secondary)
                TextField("Service address",text:$address)
                SecureField("Connection key",text:$key)
                Text(sync.message).font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Cancel") {key = ""; showSetup = false}
                    Spacer()
                    Button("Save connection") {Task {await sync.configure(address:address,token:key); if sync.configured && sync.serviceAddress == address {key = "";showSetup = false}}}.disabled(key.isEmpty || sync.busy)
                }
            }.padding(26).frame(width:510)
        }
        .alert("Revoke bank access?",isPresented:$confirmDisconnect) {
            Button("Cancel",role:.cancel) {}
            Button("Disconnect",role:.destructive) {Task {await sync.disconnect()}}
        } message: {Text("Stops syncing and revokes the provider sessions. Your imported transactions stay in Mochi Money.")}
    }
}
