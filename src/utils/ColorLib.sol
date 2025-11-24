// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ColorLib
 * @notice Color manipulation utilities for on-chain generative art
 * @dev Provides HSL/RGB conversion, color palettes, gradients, and color math
 */
library ColorLib {
    // ============ CONSTANTS ============

    /// @notice Fixed-point precision (1000 = 1.0)
    uint256 internal constant PRECISION = 1000;

    /// @notice Maximum RGB component value
    uint256 internal constant MAX_RGB = 255;

    /// @notice Maximum hue value (degrees)
    uint256 internal constant MAX_HUE = 360;

    // ============ TYPES ============

    /// @notice RGB color representation
    struct RGB {
        uint8 r;
        uint8 g;
        uint8 b;
    }

    /// @notice HSL color representation (values scaled by PRECISION)
    struct HSL {
        uint256 h; // Hue: 0-360
        uint256 s; // Saturation: 0-1000 (0-100%)
        uint256 l; // Lightness: 0-1000 (0-100%)
    }

    /// @notice HSV color representation (values scaled by PRECISION)
    struct HSV {
        uint256 h; // Hue: 0-360
        uint256 s; // Saturation: 0-1000 (0-100%)
        uint256 v; // Value: 0-1000 (0-100%)
    }

    /// @notice Color palette configuration
    struct Palette {
        string[] colors; // Hex colors (without #)
        string name; // Palette name
    }

    // ============ HEX STRING CONVERSION ============

    /**
     * @notice Converts RGB to hex string (without #)
     * @param color RGB color
     * @return Hex string representation
     */
    function toHex(RGB memory color) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                _byteToHex(color.r),
                _byteToHex(color.g),
                _byteToHex(color.b)
            )
        );
    }

    /**
     * @notice Converts RGB components to hex string
     * @param r Red component (0-255)
     * @param g Green component (0-255)
     * @param b Blue component (0-255)
     * @return Hex string representation
     */
    function toHex(uint8 r, uint8 g, uint8 b) internal pure returns (string memory) {
        return toHex(RGB(r, g, b));
    }

    /**
     * @notice Converts hex string to RGB
     * @param hexColor Hex color string (6 characters, without #)
     * @return RGB color
     */
    function fromHex(string memory hexColor) internal pure returns (RGB memory) {
        bytes memory hexBytes = bytes(hexColor);
        require(hexBytes.length == 6, "Invalid hex length");

        return RGB(
            uint8(_hexCharToValue(hexBytes[0]) * 16 + _hexCharToValue(hexBytes[1])),
            uint8(_hexCharToValue(hexBytes[2]) * 16 + _hexCharToValue(hexBytes[3])),
            uint8(_hexCharToValue(hexBytes[4]) * 16 + _hexCharToValue(hexBytes[5]))
        );
    }

    // ============ COLOR SPACE CONVERSION ============

    /**
     * @notice Converts HSL to RGB
     * @param hsl HSL color
     * @return RGB color
     */
    function hslToRgb(HSL memory hsl) internal pure returns (RGB memory) {
        if (hsl.s == 0) {
            // Achromatic (grayscale)
            uint8 gray = uint8((hsl.l * MAX_RGB) / PRECISION);
            return RGB(gray, gray, gray);
        }

        uint256 q;
        if (hsl.l < 500) {
            q = (hsl.l * (PRECISION + hsl.s)) / PRECISION;
        } else {
            q = hsl.l + hsl.s - (hsl.l * hsl.s) / PRECISION;
        }

        uint256 p = 2 * hsl.l - q;

        uint256 r = _hueToRgb(p, q, (hsl.h + 120) % 360);
        uint256 g = _hueToRgb(p, q, hsl.h);
        uint256 b = _hueToRgb(p, q, (hsl.h + 240) % 360);

        return RGB(
            uint8((r * MAX_RGB) / PRECISION),
            uint8((g * MAX_RGB) / PRECISION),
            uint8((b * MAX_RGB) / PRECISION)
        );
    }

    /**
     * @notice Converts RGB to HSL
     * @param rgb RGB color
     * @return HSL color
     */
    function rgbToHsl(RGB memory rgb) internal pure returns (HSL memory) {
        uint256 r = (uint256(rgb.r) * PRECISION) / MAX_RGB;
        uint256 g = (uint256(rgb.g) * PRECISION) / MAX_RGB;
        uint256 b = (uint256(rgb.b) * PRECISION) / MAX_RGB;

        uint256 maxVal = _max3(r, g, b);
        uint256 minVal = _min3(r, g, b);
        uint256 l = (maxVal + minVal) / 2;

        if (maxVal == minVal) {
            return HSL(0, 0, l); // Achromatic
        }

        uint256 d = maxVal - minVal;
        uint256 s;

        if (l > 500) {
            s = (d * PRECISION) / (2 * PRECISION - maxVal - minVal);
        } else {
            s = (d * PRECISION) / (maxVal + minVal);
        }

        uint256 h;
        if (maxVal == r) {
            h = ((g >= b ? g - b : b - g) * 60) / d;
            if (g < b) h = 360 - h;
        } else if (maxVal == g) {
            h = 120 + ((b >= r ? b - r : r - b) * 60) / d;
            if (b < r) h = 240 - h + 120;
        } else {
            h = 240 + ((r >= g ? r - g : g - r) * 60) / d;
            if (r < g) h = 480 - h;
        }

        return HSL(h % 360, s, l);
    }

    /**
     * @notice Converts HSV to RGB
     * @param hsv HSV color
     * @return RGB color
     */
    function hsvToRgb(HSV memory hsv) internal pure returns (RGB memory) {
        if (hsv.s == 0) {
            uint8 gray = uint8((hsv.v * MAX_RGB) / PRECISION);
            return RGB(gray, gray, gray);
        }

        uint256 h = hsv.h;
        uint256 s = hsv.s;
        uint256 v = hsv.v;

        uint256 i = (h * 6) / 360;
        uint256 f = ((h * 6) % 360) * PRECISION / 360;

        uint256 p = (v * (PRECISION - s)) / PRECISION;
        uint256 q = (v * (PRECISION - (s * f) / PRECISION)) / PRECISION;
        uint256 t = (v * (PRECISION - (s * (PRECISION - f)) / PRECISION)) / PRECISION;

        uint256 r;
        uint256 g;
        uint256 b;

        if (i == 0) { r = v; g = t; b = p; }
        else if (i == 1) { r = q; g = v; b = p; }
        else if (i == 2) { r = p; g = v; b = t; }
        else if (i == 3) { r = p; g = q; b = v; }
        else if (i == 4) { r = t; g = p; b = v; }
        else { r = v; g = p; b = q; }

        return RGB(
            uint8((r * MAX_RGB) / PRECISION),
            uint8((g * MAX_RGB) / PRECISION),
            uint8((b * MAX_RGB) / PRECISION)
        );
    }

    // ============ COLOR MANIPULATION ============

    /**
     * @notice Lighten a color
     * @param color RGB color
     * @param amount Amount to lighten (0-1000)
     * @return Lightened RGB color
     */
    function lighten(RGB memory color, uint256 amount) internal pure returns (RGB memory) {
        HSL memory hsl = rgbToHsl(color);
        hsl.l = hsl.l + ((PRECISION - hsl.l) * amount) / PRECISION;
        if (hsl.l > PRECISION) hsl.l = PRECISION;
        return hslToRgb(hsl);
    }

    /**
     * @notice Darken a color
     * @param color RGB color
     * @param amount Amount to darken (0-1000)
     * @return Darkened RGB color
     */
    function darken(RGB memory color, uint256 amount) internal pure returns (RGB memory) {
        HSL memory hsl = rgbToHsl(color);
        hsl.l = (hsl.l * (PRECISION - amount)) / PRECISION;
        return hslToRgb(hsl);
    }

    /**
     * @notice Saturate a color
     * @param color RGB color
     * @param amount Amount to saturate (0-1000)
     * @return Saturated RGB color
     */
    function saturate(RGB memory color, uint256 amount) internal pure returns (RGB memory) {
        HSL memory hsl = rgbToHsl(color);
        hsl.s = hsl.s + ((PRECISION - hsl.s) * amount) / PRECISION;
        if (hsl.s > PRECISION) hsl.s = PRECISION;
        return hslToRgb(hsl);
    }

    /**
     * @notice Desaturate a color
     * @param color RGB color
     * @param amount Amount to desaturate (0-1000)
     * @return Desaturated RGB color
     */
    function desaturate(RGB memory color, uint256 amount) internal pure returns (RGB memory) {
        HSL memory hsl = rgbToHsl(color);
        hsl.s = (hsl.s * (PRECISION - amount)) / PRECISION;
        return hslToRgb(hsl);
    }

    /**
     * @notice Rotate hue by degrees
     * @param color RGB color
     * @param degrees Degrees to rotate (0-360)
     * @return Color with rotated hue
     */
    function rotateHue(RGB memory color, uint256 degrees) internal pure returns (RGB memory) {
        HSL memory hsl = rgbToHsl(color);
        hsl.h = (hsl.h + degrees) % 360;
        return hslToRgb(hsl);
    }

    /**
     * @notice Get complementary color (180° hue rotation)
     * @param color RGB color
     * @return Complementary RGB color
     */
    function complement(RGB memory color) internal pure returns (RGB memory) {
        return rotateHue(color, 180);
    }

    /**
     * @notice Invert a color
     * @param color RGB color
     * @return Inverted RGB color
     */
    function invert(RGB memory color) internal pure returns (RGB memory) {
        return RGB(
            uint8(MAX_RGB - color.r),
            uint8(MAX_RGB - color.g),
            uint8(MAX_RGB - color.b)
        );
    }

    /**
     * @notice Convert to grayscale
     * @param color RGB color
     * @return Grayscale RGB color
     */
    function grayscale(RGB memory color) internal pure returns (RGB memory) {
        // Use luminosity method (weighted average)
        uint8 gray = uint8((uint256(color.r) * 299 + uint256(color.g) * 587 + uint256(color.b) * 114) / 1000);
        return RGB(gray, gray, gray);
    }

    // ============ COLOR BLENDING ============

    /**
     * @notice Blend two colors
     * @param color1 First RGB color
     * @param color2 Second RGB color
     * @param t Blend factor (0-1000, 0=color1, 1000=color2)
     * @return Blended RGB color
     */
    function blend(RGB memory color1, RGB memory color2, uint256 t) internal pure returns (RGB memory) {
        return RGB(
            uint8(_lerp(color1.r, color2.r, t)),
            uint8(_lerp(color1.g, color2.g, t)),
            uint8(_lerp(color1.b, color2.b, t))
        );
    }

    /**
     * @notice Mix multiple colors equally
     * @param colors Array of RGB colors
     * @return Mixed RGB color
     */
    function mix(RGB[] memory colors) internal pure returns (RGB memory) {
        require(colors.length > 0, "Empty color array");

        uint256 totalR;
        uint256 totalG;
        uint256 totalB;

        for (uint256 i = 0; i < colors.length; i++) {
            totalR += colors[i].r;
            totalG += colors[i].g;
            totalB += colors[i].b;
        }

        return RGB(
            uint8(totalR / colors.length),
            uint8(totalG / colors.length),
            uint8(totalB / colors.length)
        );
    }

    /**
     * @notice Alpha blend two colors
     * @param foreground Foreground RGB color
     * @param background Background RGB color
     * @param alpha Alpha value (0-1000, 1000=fully opaque)
     * @return Blended RGB color
     */
    function alphaBlend(RGB memory foreground, RGB memory background, uint256 alpha)
        internal
        pure
        returns (RGB memory)
    {
        return blend(background, foreground, alpha);
    }

    // ============ COLOR HARMONY ============

    /**
     * @notice Generate analogous colors (adjacent on color wheel)
     * @param baseColor Base RGB color
     * @param angle Angle separation (typically 30)
     * @return Array of 3 analogous colors
     */
    function analogous(RGB memory baseColor, uint256 angle) internal pure returns (RGB[3] memory) {
        return [
            rotateHue(baseColor, 360 - angle),
            baseColor,
            rotateHue(baseColor, angle)
        ];
    }

    /**
     * @notice Generate triadic colors (120° apart)
     * @param baseColor Base RGB color
     * @return Array of 3 triadic colors
     */
    function triadic(RGB memory baseColor) internal pure returns (RGB[3] memory) {
        return [
            baseColor,
            rotateHue(baseColor, 120),
            rotateHue(baseColor, 240)
        ];
    }

    /**
     * @notice Generate tetradic colors (90° apart)
     * @param baseColor Base RGB color
     * @return Array of 4 tetradic colors
     */
    function tetradic(RGB memory baseColor) internal pure returns (RGB[4] memory) {
        return [
            baseColor,
            rotateHue(baseColor, 90),
            rotateHue(baseColor, 180),
            rotateHue(baseColor, 270)
        ];
    }

    /**
     * @notice Generate split-complementary colors
     * @param baseColor Base RGB color
     * @param angle Split angle from complement (typically 30)
     * @return Array of 3 split-complementary colors
     */
    function splitComplementary(RGB memory baseColor, uint256 angle) internal pure returns (RGB[3] memory) {
        return [
            baseColor,
            rotateHue(baseColor, 180 - angle),
            rotateHue(baseColor, 180 + angle)
        ];
    }

    // ============ PALETTE GENERATION ============

    /**
     * @notice Generate monochromatic palette
     * @param baseColor Base RGB color
     * @param steps Number of steps
     * @return Array of colors from dark to light
     */
    function monochromatic(RGB memory baseColor, uint256 steps) internal pure returns (string[] memory) {
        require(steps > 0 && steps <= 10, "Invalid step count");

        string[] memory palette = new string[](steps);
        HSL memory hsl = rgbToHsl(baseColor);

        for (uint256 i = 0; i < steps; i++) {
            // Distribute lightness from 10% to 90%
            uint256 lightness = 100 + (i * 800) / (steps - 1 > 0 ? steps - 1 : 1);
            HSL memory variant = HSL(hsl.h, hsl.s, lightness);
            palette[i] = toHex(hslToRgb(variant));
        }

        return palette;
    }

    /**
     * @notice Generate rainbow palette
     * @param steps Number of colors
     * @param saturation Saturation (0-1000)
     * @param lightness Lightness (0-1000)
     * @return Array of rainbow colors
     */
    function rainbow(uint256 steps, uint256 saturation, uint256 lightness) internal pure returns (string[] memory) {
        require(steps > 0 && steps <= 24, "Invalid step count");

        string[] memory palette = new string[](steps);

        for (uint256 i = 0; i < steps; i++) {
            uint256 hue = (i * 360) / steps;
            HSL memory hsl = HSL(hue, saturation, lightness);
            palette[i] = toHex(hslToRgb(hsl));
        }

        return palette;
    }

    /**
     * @notice Generate gradient steps between two colors
     * @param color1 Start color
     * @param color2 End color
     * @param steps Number of steps
     * @return Array of gradient colors
     */
    function gradient(RGB memory color1, RGB memory color2, uint256 steps) internal pure returns (string[] memory) {
        require(steps > 0 && steps <= 24, "Invalid step count");

        string[] memory palette = new string[](steps);

        for (uint256 i = 0; i < steps; i++) {
            uint256 t = steps > 1 ? (i * PRECISION) / (steps - 1) : 0;
            palette[i] = toHex(blend(color1, color2, t));
        }

        return palette;
    }

    // ============ PRESET PALETTES ============

    /**
     * @notice Get sunset palette
     * @return Array of sunset colors
     */
    function sunsetPalette() internal pure returns (string[5] memory) {
        return ["FF6B6B", "FFA07A", "FFD93D", "C9B1FF", "6C5CE7"];
    }

    /**
     * @notice Get ocean palette
     * @return Array of ocean colors
     */
    function oceanPalette() internal pure returns (string[5] memory) {
        return ["0077B6", "00B4D8", "90E0EF", "CAF0F8", "023E8A"];
    }

    /**
     * @notice Get forest palette
     * @return Array of forest colors
     */
    function forestPalette() internal pure returns (string[5] memory) {
        return ["2D6A4F", "40916C", "52B788", "74C69D", "95D5B2"];
    }

    /**
     * @notice Get fire palette
     * @return Array of fire colors
     */
    function firePalette() internal pure returns (string[5] memory) {
        return ["FF0000", "FF4500", "FF8C00", "FFD700", "FFFF00"];
    }

    /**
     * @notice Get neon palette
     * @return Array of neon colors
     */
    function neonPalette() internal pure returns (string[5] memory) {
        return ["FF00FF", "00FFFF", "39FF14", "FF3F8E", "04D9FF"];
    }

    /**
     * @notice Get earth palette
     * @return Array of earth tone colors
     */
    function earthPalette() internal pure returns (string[5] memory) {
        return ["8B4513", "A0522D", "CD853F", "DEB887", "F5DEB3"];
    }

    /**
     * @notice Get cosmic palette
     * @return Array of cosmic/space colors
     */
    function cosmicPalette() internal pure returns (string[5] memory) {
        return ["0D0221", "190535", "2B1055", "7B2D8E", "D63AF9"];
    }

    /**
     * @notice Get pastel palette
     * @return Array of pastel colors
     */
    function pastelPalette() internal pure returns (string[5] memory) {
        return ["FFB3BA", "FFDFBA", "FFFFBA", "BAFFC9", "BAE1FF"];
    }

    // ============ DETERMINISTIC COLOR GENERATION ============

    /**
     * @notice Generate deterministic color from seed
     * @param seed Random seed
     * @return Hex color string
     */
    function fromSeed(uint256 seed) internal pure returns (string memory) {
        uint256 hash = uint256(keccak256(abi.encodePacked(seed)));
        return toHex(
            uint8(hash % 256),
            uint8((hash >> 8) % 256),
            uint8((hash >> 16) % 256)
        );
    }

    /**
     * @notice Generate deterministic HSL color from seed with controlled parameters
     * @param seed Random seed
     * @param minSaturation Minimum saturation (0-1000)
     * @param maxSaturation Maximum saturation (0-1000)
     * @param minLightness Minimum lightness (0-1000)
     * @param maxLightness Maximum lightness (0-1000)
     * @return Hex color string
     */
    function fromSeedConstrained(
        uint256 seed,
        uint256 minSaturation,
        uint256 maxSaturation,
        uint256 minLightness,
        uint256 maxLightness
    ) internal pure returns (string memory) {
        uint256 hash = uint256(keccak256(abi.encodePacked(seed)));

        uint256 hue = hash % 360;
        uint256 satRange = maxSaturation > minSaturation ? maxSaturation - minSaturation : 0;
        uint256 saturation = minSaturation + ((hash >> 16) % (satRange + 1));
        uint256 lightRange = maxLightness > minLightness ? maxLightness - minLightness : 0;
        uint256 lightness = minLightness + ((hash >> 32) % (lightRange + 1));

        return toHex(hslToRgb(HSL(hue, saturation, lightness)));
    }

    /**
     * @notice Generate palette from seed
     * @param seed Random seed
     * @param count Number of colors
     * @return Array of hex color strings
     */
    function paletteFromSeed(uint256 seed, uint256 count) internal pure returns (string[] memory) {
        require(count > 0 && count <= 12, "Invalid count");

        string[] memory palette = new string[](count);

        // Generate base color from seed
        uint256 baseHash = uint256(keccak256(abi.encodePacked(seed)));
        uint256 baseHue = baseHash % 360;

        // Determine harmony type from seed
        uint256 harmonyType = (baseHash >> 24) % 4;

        for (uint256 i = 0; i < count; i++) {
            uint256 hue;
            if (harmonyType == 0) {
                // Analogous
                hue = (baseHue + i * 30) % 360;
            } else if (harmonyType == 1) {
                // Triadic
                hue = (baseHue + i * 120) % 360;
            } else if (harmonyType == 2) {
                // Complementary split
                hue = (baseHue + (i % 2 == 0 ? 0 : 180) + i * 15) % 360;
            } else {
                // Tetradic
                hue = (baseHue + i * 90) % 360;
            }

            uint256 itemHash = uint256(keccak256(abi.encodePacked(seed, i)));
            uint256 saturation = 600 + (itemHash % 400); // 60-100%
            uint256 lightness = 400 + ((itemHash >> 8) % 300); // 40-70%

            palette[i] = toHex(hslToRgb(HSL(hue, saturation, lightness)));
        }

        return palette;
    }

    // ============ INTERNAL HELPERS ============

    /**
     * @notice Convert byte to 2-character hex string
     */
    function _byteToHex(uint8 value) internal pure returns (string memory) {
        bytes memory hexChars = "0123456789ABCDEF";
        bytes memory result = new bytes(2);
        result[0] = hexChars[value >> 4];
        result[1] = hexChars[value & 0x0f];
        return string(result);
    }

    /**
     * @notice Convert hex character to value
     */
    function _hexCharToValue(bytes1 c) internal pure returns (uint8) {
        if (c >= "0" && c <= "9") {
            return uint8(c) - uint8(bytes1("0"));
        }
        if (c >= "a" && c <= "f") {
            return uint8(c) - uint8(bytes1("a")) + 10;
        }
        if (c >= "A" && c <= "F") {
            return uint8(c) - uint8(bytes1("A")) + 10;
        }
        revert("Invalid hex character");
    }

    /**
     * @notice Helper for HSL to RGB conversion
     */
    function _hueToRgb(uint256 p, uint256 q, uint256 t) internal pure returns (uint256) {
        if (t < 60) return p + ((q - p) * t * 6) / 360;
        if (t < 180) return q;
        if (t < 240) return p + ((q - p) * (240 - t) * 6) / 360;
        return p;
    }

    /**
     * @notice Linear interpolation
     */
    function _lerp(uint8 a, uint8 b, uint256 t) internal pure returns (uint256) {
        if (t == 0) return a;
        if (t >= PRECISION) return b;
        return uint256(a) + ((uint256(b) - uint256(a)) * t) / PRECISION;
    }

    /**
     * @notice Maximum of three values
     */
    function _max3(uint256 a, uint256 b, uint256 c) internal pure returns (uint256) {
        return a >= b ? (a >= c ? a : c) : (b >= c ? b : c);
    }

    /**
     * @notice Minimum of three values
     */
    function _min3(uint256 a, uint256 b, uint256 c) internal pure returns (uint256) {
        return a <= b ? (a <= c ? a : c) : (b <= c ? b : c);
    }
}
