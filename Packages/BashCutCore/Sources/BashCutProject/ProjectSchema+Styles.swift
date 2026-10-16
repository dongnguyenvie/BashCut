import Foundation

extension ProjectSchema {
    /// `textStyle.lines` (`TextLineStyles`): each line's own look, in reading order.
    static var textLinesSchema: JSONValue {
        let color: JSONValue = .object(["type": .string("string"), "pattern": .string("^#[0-9A-Fa-f]{6}$")])
        return .object([
            "type": .string("array"), "maxItems": .integer(TextLineStyles.maximumLines),
            "description": .string("Each line's own look in reading order (two fonts in one title); null keeps the block's"),
            "items": .object([
                "type": .array([.string("object"), .string("null")]), "additionalProperties": .bool(false),
                "properties": .object([
                    "font": .object(["type": .string("string"), "minLength": .integer(1), "maxLength": .integer(128),
                                     "description": .string("Font PostScript name (family and weight)")]),
                    "scale": .object(["type": .string("number"), "minimum": .number(TextLineStyles.scaleRange.lowerBound),
                                      "maximum": .number(TextLineStyles.scaleRange.upperBound),
                                      "description": .string("Size × the block's font size")]),
                    "fill": color, "stroke": color,
                ]),
            ]),
        ])
    }
}

extension ItemProperty {
    /// The item backdrop (P3-J7): what fills the frame around a fitted picture.
    static let backdropProperties: [ItemProperty] = [
        .init("backdrop", "kind", .text(maxLength: 5),
              "Video picture: what fills the frame around a fitted picture: blur (a blurred, filled copy of itself) or color"),
        .init("backdrop", "color", .color, "Backdrop colour #RRGGBB (kind color; default black)"),
        .init("backdrop", "blur", .number(0...0.5), "Blur radius as a share of the frame's short side (kind blur; default 0.05)"),
        .init("backdrop", "dim", .number(0...1), "Darkens the backdrop: 0 unchanged, 1 black (default 0)"),
    ]

    /// Picture fields of video and image clips beyond transform, crop and colour.
    static let pictureProperties: [ItemProperty] = [
        .init(nil, "blur", .number(0...0.2),
              "Video or image picture: Gaussian blur radius as a share of the picture's short side, after the crop (0.02 softens, 0.04 hides text)"),
        .init(nil, "pixelate", .number(0...0.1),
              "Video or image picture: mosaic cell size as a share of the picture's short side, after the crop and before the blur"),
        .init(nil, "feather", .number(0...0.5),
              "Video or image picture: its edges fade out over this share of its shorter side (after crop, mosaic and blur)"),
    ]
}
