module JasperHTML
  module Constants
    VOID_ELEMENTS = Set{
      "area", "base", "br", "col", "embed", "hr", "img", "input",
      "link", "meta", "param", "source", "track", "wbr",
    }

    SPECIAL_ELEMENTS = Set{
      "address", "applet", "area", "article", "aside", "base", "basefont",
      "bgsound", "blockquote", "body", "br", "button", "caption", "center",
      "col", "colgroup", "dd", "details", "dir", "div", "dl", "dt", "embed",
      "fieldset", "figcaption", "figure", "footer", "form", "frame", "frameset",
      "h1", "h2", "h3", "h4", "h5", "h6", "head", "header", "hgroup", "hr",
      "html", "iframe", "img", "input", "keygen", "li", "link", "listing",
      "main", "marquee", "menu", "meta", "nav", "noembed", "noframes",
      "noscript", "object", "ol", "p", "param", "plaintext", "pre", "script",
      "search", "section", "select", "source", "style", "summary", "table",
      "tbody", "td", "template", "textarea", "tfoot", "th", "thead", "title",
      "tr", "track", "ul", "wbr", "xmp",
    }

    FORMATTING_ELEMENTS = Set{
      "a", "b", "big", "code", "em", "font", "i", "nobr", "s", "small",
      "strike", "strong", "tt", "u",
    }

    RCDATA_ELEMENTS = Set{"title", "textarea"}

    RAWTEXT_ELEMENTS = Set{
      "script", "style", "xmp", "iframe", "noembed", "noframes",
    }

    FOREIGN_ATTRIBUTE_ADJUSTMENTS = {
      "xlink:actuate" => {"xlink", "actuate", "http://www.w3.org/1999/xlink"},
      "xlink:arcrole" => {"xlink", "arcrole", "http://www.w3.org/1999/xlink"},
      "xlink:href"    => {"xlink", "href", "http://www.w3.org/1999/xlink"},
      "xlink:role"    => {"xlink", "role", "http://www.w3.org/1999/xlink"},
      "xlink:show"    => {"xlink", "show", "http://www.w3.org/1999/xlink"},
      "xlink:title"   => {"xlink", "title", "http://www.w3.org/1999/xlink"},
      "xlink:type"    => {"xlink", "type", "http://www.w3.org/1999/xlink"},
      "xml:lang"      => {"xml", "lang", "http://www.w3.org/XML/1998/namespace"},
      "xml:space"     => {"xml", "space", "http://www.w3.org/XML/1998/namespace"},
      "xmlns"         => {nil, "xmlns", "http://www.w3.org/2000/xmlns/"},
      "xmlns:xlink"   => {"xmlns", "xlink", "http://www.w3.org/2000/xmlns/"},
    }

    SVG_TAG_ADJUSTMENTS = {
      "altglyph"            => "altGlyph",
      "altglyphdef"         => "altGlyphDef",
      "altglyphitem"        => "altGlyphItem",
      "animatecolor"        => "animateColor",
      "animatemotion"       => "animateMotion",
      "animatetransform"    => "animateTransform",
      "clippath"            => "clipPath",
      "feblend"             => "feBlend",
      "fecolormatrix"       => "feColorMatrix",
      "fecomponenttransfer" => "feComponentTransfer",
      "fecomposite"         => "feComposite",
      "feconvolvematrix"    => "feConvolveMatrix",
      "fediffuselighting"   => "feDiffuseLighting",
      "fedisplacementmap"   => "feDisplacementMap",
      "fedistantlight"      => "feDistantLight",
      "fedropshadow"        => "feDropShadow",
      "feflood"             => "feFlood",
      "fefunca"             => "feFuncA",
      "fefuncb"             => "feFuncB",
      "fefuncg"             => "feFuncG",
      "fefuncr"             => "feFuncR",
      "fegaussianblur"      => "feGaussianBlur",
      "feimage"             => "feImage",
      "femerge"             => "feMerge",
      "femergenode"         => "feMergeNode",
      "femorphology"        => "feMorphology",
      "feoffset"            => "feOffset",
      "fepointlight"        => "fePointLight",
      "fespecularlighting"  => "feSpecularLighting",
      "fespotlight"         => "feSpotLight",
      "fetile"              => "feTile",
      "feturbulence"        => "feTurbulence",
      "foreignobject"       => "foreignObject",
      "glyphref"            => "glyphRef",
      "lineargradient"      => "linearGradient",
      "radialgradient"      => "radialGradient",
      "textpath"            => "textPath",
    }

    SVG_ATTRIBUTE_ADJUSTMENTS = {
      "attributename"       => "attributeName",
      "attributetype"       => "attributeType",
      "basefrequency"       => "baseFrequency",
      "baseprofile"         => "baseProfile",
      "calcmode"            => "calcMode",
      "clippathunits"       => "clipPathUnits",
      "diffuseconstant"     => "diffuseConstant",
      "edgemode"            => "edgeMode",
      "filterunits"         => "filterUnits",
      "glyphref"            => "glyphRef",
      "gradienttransform"   => "gradientTransform",
      "gradientunits"       => "gradientUnits",
      "kernelmatrix"        => "kernelMatrix",
      "kernelunitlength"    => "kernelUnitLength",
      "keypoints"           => "keyPoints",
      "keysplines"          => "keySplines",
      "keytimes"            => "keyTimes",
      "lengthadjust"        => "lengthAdjust",
      "limitingconeangle"   => "limitingConeAngle",
      "markerheight"        => "markerHeight",
      "markerunits"         => "markerUnits",
      "markerwidth"         => "markerWidth",
      "maskcontentunits"    => "maskContentUnits",
      "maskunits"           => "maskUnits",
      "numoctaves"          => "numOctaves",
      "pathlength"          => "pathLength",
      "patterncontentunits" => "patternContentUnits",
      "patterntransform"    => "patternTransform",
      "patternunits"        => "patternUnits",
      "pointsatx"           => "pointsAtX",
      "pointsaty"           => "pointsAtY",
      "pointsatz"           => "pointsAtZ",
      "preservealpha"       => "preserveAlpha",
      "preserveaspectratio" => "preserveAspectRatio",
      "primitiveunits"      => "primitiveUnits",
      "refx"                => "refX",
      "refy"                => "refY",
      "repeatcount"         => "repeatCount",
      "repeatdur"           => "repeatDur",
      "requiredextensions"  => "requiredExtensions",
      "requiredfeatures"    => "requiredFeatures",
      "specularconstant"    => "specularConstant",
      "specularexponent"    => "specularExponent",
      "spreadmethod"        => "spreadMethod",
      "startoffset"         => "startOffset",
      "stddeviation"        => "stdDeviation",
      "stitchtiles"         => "stitchTiles",
      "surfacescale"        => "surfaceScale",
      "systemlanguage"      => "systemLanguage",
      "tablevalues"         => "tableValues",
      "targetx"             => "targetX",
      "targety"             => "targetY",
      "textlength"          => "textLength",
      "viewbox"             => "viewBox",
      "viewtarget"          => "viewTarget",
      "xchannelselector"    => "xChannelSelector",
      "ychannelselector"    => "yChannelSelector",
      "zoomandpan"          => "zoomAndPan",
    }

    MATHML_ATTRIBUTE_ADJUSTMENTS = {
      "definitionurl" => "definitionURL",
    }

    NAMESPACE_HTML   = "html"
    NAMESPACE_SVG    = "svg"
    NAMESPACE_MATHML = "mathml"
  end
end
