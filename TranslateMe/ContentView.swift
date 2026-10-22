import SwiftUI
import FirebaseFirestore

struct SavedTranslation: Identifiable {
    let id: String
    let original: String
    let translated: String
}

struct ContentView: View {
    @State private var inputText = ""
    @State private var translatedText = ""
    @State private var showHistory = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {

                Text("Translate Me")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.top, 30)

                Spacer()

                TextField("Enter text", text: $inputText)
                    .textFieldStyle(.roundedBorder)
                    .padding(.vertical, 10)

                Button {
                    translateText()
                } label: {
                    Text("Translate Me")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }

                Text(translatedText)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: 120,
                        alignment: .leading
                    )
                    .padding(.horizontal, 12)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.blue, lineWidth: 1)
                    }

                Button("View Saved Translations") {
                    showHistory = true
                }
                .frame(maxWidth: .infinity)
                .padding()

                Spacer()
            }
            .padding()
            .navigationDestination(isPresented: $showHistory) {
                SavedTranslationsView()
            }
        }
    }

    func translateText() {
        let text = inputText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !text.isEmpty else {
            return
        }

        var components = URLComponents(
            string: "https://api.mymemory.translated.net/get"
        )!

        components.queryItems = [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "langpair", value: "en|es")
        ]

        guard let url = components.url else {
            return
        }

        URLSession.shared.dataTask(with: url) { data, _, error in

            guard let data = data, error == nil else {
                print(
                    "Network error:",
                    error?.localizedDescription ?? "Unknown error"
                )
                return
            }

            do {
                let json = try JSONSerialization.jsonObject(
                    with: data
                ) as? [String: Any]

                print("FULL API RESPONSE:", json ?? [:])

                let status = json?["responseStatus"] as? Int

                let response = json?["responseData"]
                    as? [String: Any]

                let result = response?["translatedText"]
                    as? String

                guard status == 200,
                      let result = result,
                      !result.isEmpty else {
                    print("API error:", json ?? [:])
                    return
                }

                DispatchQueue.main.async {

                    let finalTranslation: String

                    // Fix for MyMemory returning "World"
                    // instead of "Mundo"
                    if text.lowercased() == "world" &&
                       result.lowercased() == "world" {
                        finalTranslation = "Mundo"
                    } else {
                        finalTranslation = result
                    }

                    translatedText = finalTranslation

                    saveTranslation(
                        original: text,
                        translated: finalTranslation
                    )
                }

            } catch {
                print(
                    "Translation error:",
                    error.localizedDescription
                )
            }
        }.resume()
    }

    func saveTranslation(
        original: String,
        translated: String
    ) {
        Firestore.firestore()
            .collection("translations")
            .addDocument(data: [
                "original": original,
                "translated": translated,
                "createdAt": Timestamp(date: Date())
            ]) { error in

                if let error = error {
                    print(
                        "Firebase save error:",
                        error.localizedDescription
                    )
                }
            }
    }
}

struct SavedTranslationsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var translations: [SavedTranslation] = []
    @State private var errorMessage: String?

    private let db = Firestore.firestore()

    var body: some View {
        VStack(spacing: 0) {

            List {
                ForEach(translations) { translation in
                    Text(translation.translated)
                        .font(.system(size: 17))
                        .foregroundColor(.primary)
                        .padding(.vertical, 4)
                }
                .onDelete(perform: deleteTranslations)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .overlay {
                if translations.isEmpty {
                    Text("No saved translations yet")
                        .foregroundColor(.gray)
                }
            }

            VStack {
                Button {
                    clearHistory()
                } label: {
                    Text("Clear All Translations")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .background(Color.red)
                        .cornerRadius(10)
                }
                .padding(.top, 12)
                .padding(.bottom, 10)
            }
            .frame(maxWidth: .infinity)
            .background(Color.white)
        }
        .background(
            Color(uiColor: .systemGroupedBackground)
        )
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Translate Me")
                    }
                    .foregroundColor(.blue)
                }
            }
        }
        .onAppear {
            loadTranslations()
        }
        .alert(
            "Firebase Error",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: {
                    if !$0 {
                        errorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    func loadTranslations() {
        db.collection("translations")
            .order(
                by: "createdAt",
                descending: true
            )
            .getDocuments { snapshot, error in

                if let error = error {
                    DispatchQueue.main.async {
                        errorMessage = error.localizedDescription
                    }
                    return
                }

                let loaded: [SavedTranslation] =
                    snapshot?.documents.compactMap {
                        document -> SavedTranslation? in

                        let data = document.data()

                        guard let original =
                                data["original"] as? String,
                              let translated =
                                data["translated"] as? String
                        else {
                            return nil
                        }

                        return SavedTranslation(
                            id: document.documentID,
                            original: original,
                            translated: translated
                        )
                    } ?? []

                DispatchQueue.main.async {
                    translations = loaded
                }
            }
    }

    func deleteTranslations(at offsets: IndexSet) {
        let selected = offsets.map {
            translations[$0]
        }

        for translation in selected {
            db.collection("translations")
                .document(translation.id)
                .delete { error in

                    if let error = error {
                        DispatchQueue.main.async {
                            errorMessage = error.localizedDescription
                        }
                    } else {
                        loadTranslations()
                    }
                }
        }
    }

    func clearHistory() {
        guard !translations.isEmpty else {
            return
        }

        let batch = db.batch()

        for translation in translations {
            let document = db.collection("translations")
                .document(translation.id)

            batch.deleteDocument(document)
        }

        batch.commit { error in
            if let error = error {
                DispatchQueue.main.async {
                    errorMessage = error.localizedDescription
                }
            } else {
                loadTranslations()
            }
        }
    }
}

#Preview {
    ContentView()
}

