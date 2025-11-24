// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title SVGLib
 * @notice On-chain SVG generation utilities for NFT artwork
 * @dev Provides primitives for building SVG images entirely on-chain
 */
library SVGLib {
    // ============ CONSTANTS ============

    /// @notice SVG namespace and version
    string internal constant SVG_HEADER =
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ';
    string internal constant SVG_FOOTER = "</svg>";

    /// @notice Common SVG element tags
    string internal constant RECT_OPEN = "<rect ";
    string internal constant CIRCLE_OPEN = "<circle ";
    string internal constant LINE_OPEN = "<line ";
    string internal constant PATH_OPEN = "<path ";
    string internal constant POLYGON_OPEN = "<polygon ";
    string internal constant POLYLINE_OPEN = "<polyline ";
    string internal constant TEXT_OPEN = "<text ";
    string internal constant GROUP_OPEN = "<g ";
    string internal constant DEFS_OPEN = "<defs>";
    string internal constant DEFS_CLOSE = "</defs>";
    string internal constant STYLE_OPEN = "<style>";
    string internal constant STYLE_CLOSE = "</style>";
    string internal constant CLOSE_TAG = "/>";
    string internal constant CLOSE_TAG_FULL = ">";

    // ============ TYPES ============

    /// @notice 2D point with fixed-point coordinates (scaled by 1000)
    struct Point {
        int256 x;
        int256 y;
    }

    /// @notice Rectangle definition
    struct Rect {
        int256 x;
        int256 y;
        uint256 width;
        uint256 height;
    }

    /// @notice Circle definition
    struct Circle {
        int256 cx;
        int256 cy;
        uint256 r;
    }

    /// @notice Line definition
    struct Line {
        int256 x1;
        int256 y1;
        int256 x2;
        int256 y2;
    }

    /// @notice Transform parameters
    struct Transform {
        int256 translateX;
        int256 translateY;
        int256 rotate; // degrees * 1000
        int256 scale; // scale * 1000 (1000 = 1.0)
    }

    // ============ SVG DOCUMENT FUNCTIONS ============

    /**
     * @notice Creates a complete SVG document wrapper
     * @param width Canvas width
     * @param height Canvas height
     * @param content SVG content elements
     * @return Complete SVG string
     */
    function createSVG(uint256 width, uint256 height, string memory content) internal pure returns (string memory) {
        return string(
            abi.encodePacked(SVG_HEADER, uintToString(width), " ", uintToString(height), '">',
            content,
            SVG_FOOTER)
        );
    }

    /**
     * @notice Creates an SVG with background color
     * @param width Canvas width
     * @param height Canvas height
     * @param bgColor Background color (hex without #)
     * @param content SVG content elements
     * @return Complete SVG string with background
     */
    function createSVGWithBackground(
        uint256 width,
        uint256 height,
        string memory bgColor,
        string memory content
    ) internal pure returns (string memory) {
        string memory bg = rect(Rect(0, 0, width, height), bgColor, "", 0);
        return createSVG(width, height, string(abi.encodePacked(bg, content)));
    }

    /**
     * @notice Creates an SVG with gradient background
     * @param width Canvas width
     * @param height Canvas height
     * @param gradientId Gradient ID to reference
     * @param gradientDef Gradient definition
     * @param content SVG content elements
     * @return Complete SVG string with gradient background
     */
    function createSVGWithGradient(
        uint256 width,
        uint256 height,
        string memory gradientId,
        string memory gradientDef,
        string memory content
    ) internal pure returns (string memory) {
        string memory defs = string(abi.encodePacked(DEFS_OPEN, gradientDef, DEFS_CLOSE));
        string memory bg = string(
            abi.encodePacked(
                '<rect width="100%" height="100%" fill="url(#',
                gradientId,
                ')"/>'
            )
        );
        return createSVG(width, height, string(abi.encodePacked(defs, bg, content)));
    }

    // ============ SHAPE PRIMITIVES ============

    /**
     * @notice Creates a rectangle element
     * @param r Rectangle definition
     * @param fill Fill color (hex without #)
     * @param stroke Stroke color (hex without #, empty for none)
     * @param strokeWidth Stroke width
     * @return SVG rect element string
     */
    function rect(Rect memory r, string memory fill, string memory stroke, uint256 strokeWidth)
        internal
        pure
        returns (string memory)
    {
        string memory base = string(
            abi.encodePacked(
                RECT_OPEN,
                'x="', intToString(r.x), '" ',
                'y="', intToString(r.y), '" ',
                'width="', uintToString(r.width), '" ',
                'height="', uintToString(r.height), '" '
            )
        );

        return string(abi.encodePacked(base, _fillStrokeAttrs(fill, stroke, strokeWidth), CLOSE_TAG));
    }

    /**
     * @notice Creates a rectangle with rounded corners
     * @param r Rectangle definition
     * @param rx Corner radius X
     * @param ry Corner radius Y
     * @param fill Fill color
     * @param stroke Stroke color
     * @param strokeWidth Stroke width
     * @return SVG rect element with rounded corners
     */
    function roundedRect(
        Rect memory r,
        uint256 rx,
        uint256 ry,
        string memory fill,
        string memory stroke,
        uint256 strokeWidth
    ) internal pure returns (string memory) {
        string memory base = string(
            abi.encodePacked(
                RECT_OPEN,
                'x="', intToString(r.x), '" ',
                'y="', intToString(r.y), '" ',
                'width="', uintToString(r.width), '" ',
                'height="', uintToString(r.height), '" ',
                'rx="', uintToString(rx), '" ',
                'ry="', uintToString(ry), '" '
            )
        );

        return string(abi.encodePacked(base, _fillStrokeAttrs(fill, stroke, strokeWidth), CLOSE_TAG));
    }

    /**
     * @notice Creates a circle element
     * @param c Circle definition
     * @param fill Fill color
     * @param stroke Stroke color
     * @param strokeWidth Stroke width
     * @return SVG circle element string
     */
    function circle(Circle memory c, string memory fill, string memory stroke, uint256 strokeWidth)
        internal
        pure
        returns (string memory)
    {
        string memory base = string(
            abi.encodePacked(
                CIRCLE_OPEN,
                'cx="', intToString(c.cx), '" ',
                'cy="', intToString(c.cy), '" ',
                'r="', uintToString(c.r), '" '
            )
        );

        return string(abi.encodePacked(base, _fillStrokeAttrs(fill, stroke, strokeWidth), CLOSE_TAG));
    }

    /**
     * @notice Creates a line element
     * @param l Line definition
     * @param stroke Stroke color
     * @param strokeWidth Stroke width
     * @return SVG line element string
     */
    function line(Line memory l, string memory stroke, uint256 strokeWidth) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                LINE_OPEN,
                'x1="', intToString(l.x1), '" ',
                'y1="', intToString(l.y1), '" ',
                'x2="', intToString(l.x2), '" ',
                'y2="', intToString(l.y2), '" ',
                'stroke="#', stroke, '" ',
                'stroke-width="', uintToString(strokeWidth), '"',
                CLOSE_TAG
            )
        );
    }

    /**
     * @notice Creates a polygon element from points array
     * @param points Array of points
     * @param fill Fill color
     * @param stroke Stroke color
     * @param strokeWidth Stroke width
     * @return SVG polygon element string
     */
    function polygon(Point[] memory points, string memory fill, string memory stroke, uint256 strokeWidth)
        internal
        pure
        returns (string memory)
    {
        string memory pointsStr = _pointsToString(points);
        return string(
            abi.encodePacked(
                POLYGON_OPEN,
                'points="', pointsStr, '" ',
                _fillStrokeAttrs(fill, stroke, strokeWidth),
                CLOSE_TAG
            )
        );
    }

    /**
     * @notice Creates a triangle element
     * @param p1 First vertex
     * @param p2 Second vertex
     * @param p3 Third vertex
     * @param fill Fill color
     * @param stroke Stroke color
     * @param strokeWidth Stroke width
     * @return SVG polygon element for triangle
     */
    function triangle(
        Point memory p1,
        Point memory p2,
        Point memory p3,
        string memory fill,
        string memory stroke,
        uint256 strokeWidth
    ) internal pure returns (string memory) {
        Point[] memory points = new Point[](3);
        points[0] = p1;
        points[1] = p2;
        points[2] = p3;
        return polygon(points, fill, stroke, strokeWidth);
    }

    /**
     * @notice Creates a polyline element (open path)
     * @param points Array of points
     * @param stroke Stroke color
     * @param strokeWidth Stroke width
     * @return SVG polyline element string
     */
    function polyline(Point[] memory points, string memory stroke, uint256 strokeWidth)
        internal
        pure
        returns (string memory)
    {
        string memory pointsStr = _pointsToString(points);
        return string(
            abi.encodePacked(
                POLYLINE_OPEN,
                'points="', pointsStr, '" ',
                'fill="none" ',
                'stroke="#', stroke, '" ',
                'stroke-width="', uintToString(strokeWidth), '"',
                CLOSE_TAG
            )
        );
    }

    // ============ PATH FUNCTIONS ============

    /**
     * @notice Creates a path element with custom path data
     * @param pathData SVG path data string (d attribute)
     * @param fill Fill color
     * @param stroke Stroke color
     * @param strokeWidth Stroke width
     * @return SVG path element string
     */
    function path(string memory pathData, string memory fill, string memory stroke, uint256 strokeWidth)
        internal
        pure
        returns (string memory)
    {
        return string(
            abi.encodePacked(
                PATH_OPEN,
                'd="', pathData, '" ',
                _fillStrokeAttrs(fill, stroke, strokeWidth),
                CLOSE_TAG
            )
        );
    }

    /**
     * @notice Creates move-to path command
     * @param p Point to move to
     * @return Path command string
     */
    function moveTo(Point memory p) internal pure returns (string memory) {
        return string(abi.encodePacked("M", intToString(p.x), " ", intToString(p.y), " "));
    }

    /**
     * @notice Creates line-to path command
     * @param p Point to draw line to
     * @return Path command string
     */
    function lineTo(Point memory p) internal pure returns (string memory) {
        return string(abi.encodePacked("L", intToString(p.x), " ", intToString(p.y), " "));
    }

    /**
     * @notice Creates close path command
     * @return Path command string
     */
    function closePath() internal pure returns (string memory) {
        return "Z ";
    }

    /**
     * @notice Creates quadratic bezier curve command
     * @param control Control point
     * @param end End point
     * @return Path command string
     */
    function quadraticCurve(Point memory control, Point memory end) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                "Q", intToString(control.x), " ", intToString(control.y), " ",
                intToString(end.x), " ", intToString(end.y), " "
            )
        );
    }

    /**
     * @notice Creates cubic bezier curve command
     * @param control1 First control point
     * @param control2 Second control point
     * @param end End point
     * @return Path command string
     */
    function cubicCurve(Point memory control1, Point memory control2, Point memory end)
        internal
        pure
        returns (string memory)
    {
        return string(
            abi.encodePacked(
                "C", intToString(control1.x), " ", intToString(control1.y), " ",
                intToString(control2.x), " ", intToString(control2.y), " ",
                intToString(end.x), " ", intToString(end.y), " "
            )
        );
    }

    // ============ GROUP & TRANSFORM FUNCTIONS ============

    /**
     * @notice Creates a group element with content
     * @param content Group content
     * @param attrs Additional attributes
     * @return SVG group element string
     */
    function group(string memory content, string memory attrs) internal pure returns (string memory) {
        if (bytes(attrs).length > 0) {
            return string(abi.encodePacked("<g ", attrs, ">", content, "</g>"));
        }
        return string(abi.encodePacked("<g>", content, "</g>"));
    }

    /**
     * @notice Creates a group with transform
     * @param content Group content
     * @param t Transform parameters
     * @return SVG group element with transform
     */
    function groupWithTransform(string memory content, Transform memory t) internal pure returns (string memory) {
        string memory transformStr = _buildTransform(t);
        return string(abi.encodePacked('<g transform="', transformStr, '">', content, "</g>"));
    }

    /**
     * @notice Creates a group with opacity
     * @param content Group content
     * @param opacity Opacity value (0-1000, where 1000 = 1.0)
     * @return SVG group element with opacity
     */
    function groupWithOpacity(string memory content, uint256 opacity) internal pure returns (string memory) {
        string memory opacityStr = _decimalToString(opacity, 3);
        return string(abi.encodePacked('<g opacity="', opacityStr, '">', content, "</g>"));
    }

    // ============ GRADIENT FUNCTIONS ============

    /**
     * @notice Creates a linear gradient definition
     * @param id Gradient ID for reference
     * @param x1 Start X (percentage * 10)
     * @param y1 Start Y (percentage * 10)
     * @param x2 End X (percentage * 10)
     * @param y2 End Y (percentage * 10)
     * @param stops Gradient stop definitions
     * @return SVG linear gradient definition
     */
    function linearGradient(
        string memory id,
        uint256 x1,
        uint256 y1,
        uint256 x2,
        uint256 y2,
        string memory stops
    ) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                '<linearGradient id="', id, '" ',
                'x1="', uintToString(x1 / 10), '%" ',
                'y1="', uintToString(y1 / 10), '%" ',
                'x2="', uintToString(x2 / 10), '%" ',
                'y2="', uintToString(y2 / 10), '%">',
                stops,
                "</linearGradient>"
            )
        );
    }

    /**
     * @notice Creates a radial gradient definition
     * @param id Gradient ID for reference
     * @param cx Center X (percentage * 10)
     * @param cy Center Y (percentage * 10)
     * @param r Radius (percentage * 10)
     * @param stops Gradient stop definitions
     * @return SVG radial gradient definition
     */
    function radialGradient(string memory id, uint256 cx, uint256 cy, uint256 r, string memory stops)
        internal
        pure
        returns (string memory)
    {
        return string(
            abi.encodePacked(
                '<radialGradient id="', id, '" ',
                'cx="', uintToString(cx / 10), '%" ',
                'cy="', uintToString(cy / 10), '%" ',
                'r="', uintToString(r / 10), '%">',
                stops,
                "</radialGradient>"
            )
        );
    }

    /**
     * @notice Creates a gradient stop
     * @param offset Stop offset (percentage * 10)
     * @param color Stop color (hex without #)
     * @return SVG stop element
     */
    function gradientStop(uint256 offset, string memory color) internal pure returns (string memory) {
        return string(
            abi.encodePacked('<stop offset="', uintToString(offset / 10), '%" stop-color="#', color, '"/>')
        );
    }

    /**
     * @notice Creates a gradient stop with opacity
     * @param offset Stop offset (percentage * 10)
     * @param color Stop color (hex without #)
     * @param opacity Stop opacity (0-1000)
     * @return SVG stop element with opacity
     */
    function gradientStopWithOpacity(uint256 offset, string memory color, uint256 opacity)
        internal
        pure
        returns (string memory)
    {
        return string(
            abi.encodePacked(
                '<stop offset="', uintToString(offset / 10), '%" ',
                'stop-color="#', color, '" ',
                'stop-opacity="', _decimalToString(opacity, 3), '"/>'
            )
        );
    }

    // ============ TEXT FUNCTIONS ============

    /**
     * @notice Creates a text element
     * @param x X position
     * @param y Y position
     * @param content Text content
     * @param fontSize Font size
     * @param fill Fill color
     * @return SVG text element
     */
    function text(int256 x, int256 y, string memory content, uint256 fontSize, string memory fill)
        internal
        pure
        returns (string memory)
    {
        return string(
            abi.encodePacked(
                TEXT_OPEN,
                'x="', intToString(x), '" ',
                'y="', intToString(y), '" ',
                'font-size="', uintToString(fontSize), '" ',
                'fill="#', fill, '">',
                content,
                "</text>"
            )
        );
    }

    /**
     * @notice Creates a text element with font family
     * @param x X position
     * @param y Y position
     * @param content Text content
     * @param fontSize Font size
     * @param fontFamily Font family name
     * @param fill Fill color
     * @return SVG text element with font
     */
    function textWithFont(
        int256 x,
        int256 y,
        string memory content,
        uint256 fontSize,
        string memory fontFamily,
        string memory fill
    ) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                TEXT_OPEN,
                'x="', intToString(x), '" ',
                'y="', intToString(y), '" ',
                'font-size="', uintToString(fontSize), '" ',
                'font-family="', fontFamily, '" ',
                'fill="#', fill, '">',
                content,
                "</text>"
            )
        );
    }

    // ============ FILTER FUNCTIONS ============

    /**
     * @notice Creates a blur filter definition
     * @param id Filter ID
     * @param stdDeviation Blur amount
     * @return SVG filter definition
     */
    function blurFilter(string memory id, uint256 stdDeviation) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                '<filter id="', id, '">',
                '<feGaussianBlur stdDeviation="', uintToString(stdDeviation), '"/>',
                "</filter>"
            )
        );
    }

    /**
     * @notice Creates a glow filter definition
     * @param id Filter ID
     * @param stdDeviation Glow spread
     * @param color Glow color
     * @return SVG filter definition for glow effect
     */
    function glowFilter(string memory id, uint256 stdDeviation, string memory color)
        internal
        pure
        returns (string memory)
    {
        return string(
            abi.encodePacked(
                '<filter id="', id, '">',
                '<feGaussianBlur stdDeviation="', uintToString(stdDeviation), '" result="blur"/>',
                '<feFlood flood-color="#', color, '" result="color"/>',
                '<feComposite in="color" in2="blur" operator="in" result="glow"/>',
                '<feMerge><feMergeNode in="glow"/><feMergeNode in="SourceGraphic"/></feMerge>',
                "</filter>"
            )
        );
    }

    // ============ INTERNAL HELPERS ============

    /**
     * @notice Builds fill and stroke attributes
     */
    function _fillStrokeAttrs(string memory fill, string memory stroke, uint256 strokeWidth)
        internal
        pure
        returns (string memory)
    {
        string memory fillAttr;
        if (bytes(fill).length > 0) {
            fillAttr = string(abi.encodePacked('fill="#', fill, '" '));
        } else {
            fillAttr = 'fill="none" ';
        }

        if (bytes(stroke).length > 0 && strokeWidth > 0) {
            return string(
                abi.encodePacked(fillAttr, 'stroke="#', stroke, '" stroke-width="', uintToString(strokeWidth), '"')
            );
        }
        return fillAttr;
    }

    /**
     * @notice Converts points array to SVG points string
     */
    function _pointsToString(Point[] memory points) internal pure returns (string memory) {
        if (points.length == 0) return "";

        string memory result = string(abi.encodePacked(intToString(points[0].x), ",", intToString(points[0].y)));

        for (uint256 i = 1; i < points.length; i++) {
            result = string(abi.encodePacked(result, " ", intToString(points[i].x), ",", intToString(points[i].y)));
        }

        return result;
    }

    /**
     * @notice Builds transform attribute string
     */
    function _buildTransform(Transform memory t) internal pure returns (string memory) {
        string memory result = "";

        if (t.translateX != 0 || t.translateY != 0) {
            result = string(
                abi.encodePacked(result, "translate(", intToString(t.translateX), " ", intToString(t.translateY), ") ")
            );
        }

        if (t.rotate != 0) {
            result = string(abi.encodePacked(result, "rotate(", _decimalToString(uint256(t.rotate >= 0 ? t.rotate : -t.rotate), 3), ") "));
        }

        if (t.scale != 0 && t.scale != 1000) {
            result = string(abi.encodePacked(result, "scale(", _decimalToString(uint256(t.scale >= 0 ? t.scale : -t.scale), 3), ")"));
        }

        return result;
    }

    /**
     * @notice Converts decimal value to string (value / 10^decimals)
     */
    function _decimalToString(uint256 value, uint256 decimals) internal pure returns (string memory) {
        uint256 divisor = 10 ** decimals;
        uint256 wholePart = value / divisor;
        uint256 fracPart = value % divisor;

        if (fracPart == 0) {
            return uintToString(wholePart);
        }

        // Remove trailing zeros from fractional part
        while (fracPart > 0 && fracPart % 10 == 0) {
            fracPart /= 10;
        }

        return string(abi.encodePacked(uintToString(wholePart), ".", uintToString(fracPart)));
    }

    // ============ NUMBER CONVERSION ============

    /**
     * @notice Converts uint256 to string
     * @param value The value to convert
     * @return String representation
     */
    function uintToString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }

        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }

        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits--;
            buffer[digits] = bytes1(uint8(48 + (value % 10)));
            value /= 10;
        }

        return string(buffer);
    }

    /**
     * @notice Converts int256 to string (handles negative)
     * @param value The value to convert
     * @return String representation
     */
    function intToString(int256 value) internal pure returns (string memory) {
        if (value >= 0) {
            return uintToString(uint256(value));
        }
        return string(abi.encodePacked("-", uintToString(uint256(-value))));
    }
}
