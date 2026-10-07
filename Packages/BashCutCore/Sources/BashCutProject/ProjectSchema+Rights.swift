import Foundation

/// The rights fields of media (P2-H8).
extension ProjectSchema {
    static var mediaLicenseSchema: JSONValue {
        .object([
            "description": .string("Licence (P2-H8): free text, or {id, version, text, url, attribution}"),
            "oneOf": .array([
                .object(["type": .string("string"), "maxLength": .integer(1_000)]),
                .object(fields("Structured licence", required: ["id"], properties: [
                    "id": enumeration("Licence", LicenseTerms.Identifier.allCases.map(\.rawValue)),
                    "version": string("Licence version, such as 4.0"), "text": string("As written"),
                    "url": string("Licence or source page"), "attribution": string("The credit line it asks for"),
                ])),
            ]),
        ])
    }

    static var mediaProvenanceSchema: JSONValue {
        .object(fields(
            "Where the file came from (P2-H8)", required: [],
            properties: [
                "origin": enumeration("Origin", Provenance.origins), "sourceUrl": string("Where it was found"),
                "author": string("Who made it"), "provider": string("Provider that made or found it"),
                "model": string("Model that generated it"), "prompt": string("Prompt it was generated from"),
                "requestId": string("Stable request ID (P2-G4)"),
                "charged": number("US dollars the provider reported charging", 0...1_000_000),
                "parentMedia": string("Media it was derived from"),
                "libraryItem": string("Library item (scope:id) it was placed from"),
            ]))
    }
}
