import AppKit
import SwiftUI

/// Dialog sheet to save current player mappings as a custom profile with a user-chosen name.
struct SaveProfileSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""

    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: store.deviceMode == .gamepad ? "gamecontroller.fill" : "keyboard.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(store.deviceMode == .gamepad ? .cyan : .orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Guardar Perfil de \(store.deviceMode == .gamepad ? "Mando" : "Teclado")")
                        .font(.headline)
                    Text("Guarda los controles configurados para el Jugador \(store.player + 1). Podrás asignarle un nombre y modificarlo cuando quieras.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Nombre del perfil:")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("Ej: Mi Perfil Smash, Ataque Rápido, WASD...", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .font(.body)
            }

            HStack {
                Button("Cancelar") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Guardar Perfil") {
                    store.createProfile(name: name, mode: store.deviceMode, player: store.player)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
        .onAppear {
            let modeName = store.deviceMode == .gamepad ? "Mando" : "Teclado"
            name = "Perfil \(modeName) J\(store.player + 1)"
        }
    }
}

/// Comprehensive sheet to manage, rename, duplicate, apply and delete custom profiles.
struct ProfilesManagerSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var filterMode: String = "all" // "all", "gamepad", "keyboard"
    @State private var editingProfileID: UUID? = nil
    @State private var editingName: String = ""
    @State private var showNewProfile = false
    @State private var newProfileName: String = ""
    @State private var appliedMessage: String? = nil

    var filteredProfiles: [CustomProfile] {
        store.customProfiles.filter { prof in
            if filterMode == "all" { return true }
            return prof.mode == filterMode
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "slider.horizontal.2.square")
                    .font(.system(size: 26))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Perfiles de Controles Guardados")
                        .font(.title3.weight(.bold))
                    Text("Puedes modificar el nombre de cualquier perfil, sobrescribirlo o aplicarlo a cualquier jugador.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    showNewProfile = true
                    let modeName = store.deviceMode == .gamepad ? "Mando" : "Teclado"
                    newProfileName = "Nuevo Perfil \(modeName)"
                } label: {
                    Label("Guardar actual como nuevo", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }

            if let msg = appliedMessage {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(msg)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            }

            // Filter Tabs
            Picker("", selection: $filterMode) {
                Text("Todos (\(store.customProfiles.count))").tag("all")
                Text("Mandos (\(store.customProfiles.filter { $0.isGamepad }.count))").tag("gamepad")
                Text("Teclados (\(store.customProfiles.filter { !$0.isGamepad }.count))").tag("keyboard")
            }
            .pickerStyle(.segmented)

            // Inline New Profile Field if expanded
            if showNewProfile {
                HStack(spacing: 8) {
                    Image(systemName: store.deviceMode.icon)
                        .foregroundStyle(.tint)
                    TextField("Nombre del nuevo perfil...", text: $newProfileName)
                        .textFieldStyle(.roundedBorder)
                    Button("Guardar") {
                        store.createProfile(name: newProfileName, mode: store.deviceMode, player: store.player)
                        showNewProfile = false
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newProfileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Cancelar") { showNewProfile = false }
                }
                .padding(10)
                .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }

            // List of Profiles
            if filteredProfiles.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "tray")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("No hay perfiles guardados en esta categoría")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredProfiles) { prof in
                        ProfileRowView(
                            prof: prof,
                            editingProfileID: $editingProfileID,
                            editingName: $editingName,
                            appliedMessage: $appliedMessage
                        )
                    }
                }
                .listStyle(.inset)
                .frame(minHeight: 280)
            }

            // Bottom bar
            HStack {
                Text("Tip: Puedes hacer clic en el lápiz ✏️ junto al nombre para modificarlo directamente.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cerrar") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 620, height: 490)
    }
}

struct ProfileRowView: View {
    @EnvironmentObject var store: Store
    let prof: CustomProfile
    @Binding var editingProfileID: UUID?
    @Binding var editingName: String
    @Binding var appliedMessage: String?

    var isActive: Bool {
        store.currentProfileName(for: store.player, mode: prof.isGamepad ? .gamepad : .keyboard) == prof.name
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: prof.isGamepad ? "gamecontroller.fill" : "keyboard.fill")
                .font(.system(size: 16))
                .foregroundStyle(prof.isGamepad ? .cyan : .orange)
                .frame(width: 24)

            if editingProfileID == prof.id {
                TextField("Nombre del perfil", text: $editingName, onCommit: {
                    store.renameProfile(id: prof.id, newName: editingName)
                    editingProfileID = nil
                })
                .textFieldStyle(.roundedBorder)

                Button("Guardar") {
                    store.renameProfile(id: prof.id, newName: editingName)
                    editingProfileID = nil
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("Cancelar") {
                    editingProfileID = nil
                }
                .controlSize(.small)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(prof.name)
                            .font(.system(size: 13, weight: .semibold))
                        if isActive {
                            Text("Activo en J\(store.player + 1)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Color.green.opacity(0.15), in: Capsule())
                        }
                        Button {
                            editingProfileID = prof.id
                            editingName = prof.name
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Modificar / cambiar el nombre")
                    }
                    HStack(spacing: 6) {
                        Text(prof.isGamepad ? "Mando" : "Teclado")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(prof.isGamepad ? .cyan : .orange)
                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(prof.buttonCount) asignaciones")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Action buttons
            HStack(spacing: 8) {
                if isActive {
                    Button("Activo ✓") {
                        store.applyProfile(prof, to: store.player)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                } else {
                    Button("Aplicar a J\(store.player + 1)") {
                        store.applyProfile(prof, to: store.player)
                        appliedMessage = "¡Perfil \"\(prof.name)\" aplicado al Jugador \(store.player + 1)!"
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Menu {
                    Button("Modificar nombre") {
                        editingProfileID = prof.id
                        editingName = prof.name
                    }
                    Button("Sobrescribir con controles actuales de J\(store.player + 1)") {
                        store.updateProfileFromCurrent(id: prof.id, player: store.player)
                        appliedMessage = "Perfil \"\(prof.name)\" actualizado con los controles de J\(store.player + 1)."
                    }
                    Button("Duplicar perfil") {
                        store.duplicateProfile(id: prof.id)
                    }
                    Divider()
                    Button("Eliminar perfil", role: .destructive) {
                        store.deleteProfile(id: prof.id)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12))
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
            }
        }
        .padding(.vertical, 4)
    }
}
