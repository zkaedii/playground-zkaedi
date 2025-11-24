// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SVGLib} from "./SVGLib.sol";

/**
 * @title FractalLib
 * @notice On-chain fractal generation algorithms for generative NFT artwork
 * @dev Implements various fractal patterns: Sierpinski, Koch, Tree, Spiral, and more
 */
library FractalLib {
    // ============ CONSTANTS ============

    /// @notice Fixed-point precision (1000 = 1.0)
    uint256 internal constant PRECISION = 1000;

    /// @notice Square root of 3 * PRECISION / 2 (for equilateral triangles)
    uint256 internal constant SQRT3_HALF = 866; // sqrt(3)/2 * 1000

    /// @notice Pi * PRECISION
    uint256 internal constant PI = 3142;

    /// @notice Golden ratio * PRECISION
    uint256 internal constant PHI = 1618;

    /// @notice Maximum recursion depth to prevent gas exhaustion
    uint256 internal constant MAX_DEPTH = 8;

    // ============ TYPES ============

    /// @notice Configuration for Sierpinski triangle generation
    struct SierpinskiConfig {
        uint256 size; // Triangle size in pixels
        uint256 depth; // Recursion depth (1-8)
        string fillColor; // Fill color (hex without #)
        string strokeColor; // Stroke color
        uint256 strokeWidth; // Stroke width
        int256 centerX; // Center X position
        int256 centerY; // Center Y position
    }

    /// @notice Configuration for Koch snowflake generation
    struct KochConfig {
        uint256 size; // Initial side length
        uint256 depth; // Recursion depth (1-6)
        string strokeColor; // Stroke color
        uint256 strokeWidth; // Stroke width
        int256 centerX; // Center X position
        int256 centerY; // Center Y position
        bool filled; // Whether to fill the shape
        string fillColor; // Fill color if filled
    }

    /// @notice Configuration for fractal tree generation
    struct TreeConfig {
        uint256 trunkLength; // Initial trunk length
        uint256 depth; // Recursion depth (1-10)
        uint256 branchAngle; // Branch angle in degrees * 10
        uint256 lengthRatio; // Length reduction ratio (0-1000)
        uint256 widthRatio; // Width reduction ratio (0-1000)
        string[] colors; // Colors for different depth levels
        int256 startX; // Start X position
        int256 startY; // Start Y position
    }

    /// @notice Configuration for spiral fractal generation
    struct SpiralConfig {
        uint256 turns; // Number of spiral turns
        uint256 startRadius; // Starting radius
        uint256 growth; // Growth factor per turn (multiplied by 1000)
        uint256 points; // Points per turn
        string strokeColor; // Stroke color
        uint256 strokeWidth; // Stroke width
        int256 centerX; // Center X
        int256 centerY; // Center Y
    }

    /// @notice Configuration for Mandelbrot-style pattern
    struct MandelbrotConfig {
        uint256 width; // Grid width
        uint256 height; // Grid height
        uint256 maxIterations; // Max iterations per point
        int256 minReal; // Min real value * 1000
        int256 maxReal; // Max real value * 1000
        int256 minImag; // Min imaginary value * 1000
        int256 maxImag; // Max imaginary value * 1000
        string[] palette; // Color palette for iterations
    }

    /// @notice Configuration for Cantor set
    struct CantorConfig {
        uint256 width; // Initial line width
        uint256 depth; // Recursion depth
        uint256 lineHeight; // Height of each line
        uint256 gapHeight; // Gap between levels
        string color; // Line color
        int256 startX; // Start X
        int256 startY; // Start Y
    }

    /// @notice Configuration for Dragon curve
    struct DragonConfig {
        uint256 iterations; // Number of iterations
        uint256 segmentLength; // Length of each segment
        string strokeColor; // Stroke color
        uint256 strokeWidth; // Stroke width
        int256 startX; // Start X
        int256 startY; // Start Y
    }

    // ============ SIERPINSKI TRIANGLE ============

    /**
     * @notice Generates a Sierpinski triangle fractal
     * @param config Sierpinski configuration
     * @return SVG string of the fractal
     */
    function sierpinskiTriangle(SierpinskiConfig memory config) internal pure returns (string memory) {
        uint256 depth = config.depth > MAX_DEPTH ? MAX_DEPTH : config.depth;

        // Calculate triangle vertices (equilateral, pointing up)
        int256 halfSize = int256(config.size / 2);
        int256 height = int256((config.size * SQRT3_HALF) / PRECISION);

        SVGLib.Point memory top = SVGLib.Point(config.centerX, config.centerY - int256(height * 2 / 3));
        SVGLib.Point memory bottomLeft = SVGLib.Point(config.centerX - halfSize, config.centerY + int256(height / 3));
        SVGLib.Point memory bottomRight = SVGLib.Point(config.centerX + halfSize, config.centerY + int256(height / 3));

        return _sierpinskiRecursive(top, bottomLeft, bottomRight, depth, config.fillColor, config.strokeColor, config.strokeWidth);
    }

    /**
     * @notice Recursive helper for Sierpinski triangle
     */
    function _sierpinskiRecursive(
        SVGLib.Point memory top,
        SVGLib.Point memory bottomLeft,
        SVGLib.Point memory bottomRight,
        uint256 depth,
        string memory fill,
        string memory stroke,
        uint256 strokeWidth
    ) internal pure returns (string memory) {
        if (depth == 0) {
            return SVGLib.triangle(top, bottomLeft, bottomRight, fill, stroke, strokeWidth);
        }

        // Calculate midpoints
        SVGLib.Point memory midLeft = SVGLib.Point((top.x + bottomLeft.x) / 2, (top.y + bottomLeft.y) / 2);
        SVGLib.Point memory midRight = SVGLib.Point((top.x + bottomRight.x) / 2, (top.y + bottomRight.y) / 2);
        SVGLib.Point memory midBottom = SVGLib.Point((bottomLeft.x + bottomRight.x) / 2, (bottomLeft.y + bottomRight.y) / 2);

        // Recurse on three sub-triangles (skip the middle one)
        string memory topTriangle = _sierpinskiRecursive(top, midLeft, midRight, depth - 1, fill, stroke, strokeWidth);
        string memory leftTriangle = _sierpinskiRecursive(midLeft, bottomLeft, midBottom, depth - 1, fill, stroke, strokeWidth);
        string memory rightTriangle = _sierpinskiRecursive(midRight, midBottom, bottomRight, depth - 1, fill, stroke, strokeWidth);

        return string(abi.encodePacked(topTriangle, leftTriangle, rightTriangle));
    }

    // ============ SIERPINSKI CARPET ============

    /**
     * @notice Generates a Sierpinski carpet fractal
     * @param size Square size
     * @param depth Recursion depth
     * @param fillColor Fill color
     * @param centerX Center X
     * @param centerY Center Y
     * @return SVG string of the carpet
     */
    function sierpinskiCarpet(
        uint256 size,
        uint256 depth,
        string memory fillColor,
        int256 centerX,
        int256 centerY
    ) internal pure returns (string memory) {
        uint256 clampedDepth = depth > 5 ? 5 : depth; // Lower max due to 9^n growth
        int256 halfSize = int256(size / 2);
        return _carpetRecursive(centerX - halfSize, centerY - halfSize, size, clampedDepth, fillColor);
    }

    /**
     * @notice Recursive helper for Sierpinski carpet
     */
    function _carpetRecursive(int256 x, int256 y, uint256 size, uint256 depth, string memory fill)
        internal
        pure
        returns (string memory)
    {
        if (depth == 0) {
            return SVGLib.rect(SVGLib.Rect(x, y, size, size), fill, "", 0);
        }

        uint256 newSize = size / 3;
        string memory result = "";

        // Generate 8 sub-squares (skip center)
        for (uint256 row = 0; row < 3; row++) {
            for (uint256 col = 0; col < 3; col++) {
                if (row == 1 && col == 1) continue; // Skip center

                int256 newX = x + int256(col * newSize);
                int256 newY = y + int256(row * newSize);
                result = string(abi.encodePacked(result, _carpetRecursive(newX, newY, newSize, depth - 1, fill)));
            }
        }

        return result;
    }

    // ============ KOCH SNOWFLAKE ============

    /**
     * @notice Generates a Koch snowflake fractal
     * @param config Koch configuration
     * @return SVG string of the snowflake
     */
    function kochSnowflake(KochConfig memory config) internal pure returns (string memory) {
        uint256 depth = config.depth > 6 ? 6 : config.depth;

        // Calculate initial triangle vertices
        int256 halfSize = int256(config.size / 2);
        int256 height = int256((config.size * SQRT3_HALF) / PRECISION);

        SVGLib.Point memory top = SVGLib.Point(config.centerX, config.centerY - int256(height * 2 / 3));
        SVGLib.Point memory bottomLeft = SVGLib.Point(config.centerX - halfSize, config.centerY + int256(height / 3));
        SVGLib.Point memory bottomRight = SVGLib.Point(config.centerX + halfSize, config.centerY + int256(height / 3));

        // Generate Koch curve for each side
        SVGLib.Point[] memory side1 = _kochCurve(top, bottomRight, depth);
        SVGLib.Point[] memory side2 = _kochCurve(bottomRight, bottomLeft, depth);
        SVGLib.Point[] memory side3 = _kochCurve(bottomLeft, top, depth);

        // Combine all points
        uint256 totalPoints = side1.length + side2.length + side3.length - 3; // Remove duplicate endpoints
        SVGLib.Point[] memory allPoints = new SVGLib.Point[](totalPoints);

        uint256 idx = 0;
        for (uint256 i = 0; i < side1.length - 1; i++) {
            allPoints[idx++] = side1[i];
        }
        for (uint256 i = 0; i < side2.length - 1; i++) {
            allPoints[idx++] = side2[i];
        }
        for (uint256 i = 0; i < side3.length - 1; i++) {
            allPoints[idx++] = side3[i];
        }

        if (config.filled) {
            return SVGLib.polygon(allPoints, config.fillColor, config.strokeColor, config.strokeWidth);
        }
        return SVGLib.polyline(allPoints, config.strokeColor, config.strokeWidth);
    }

    /**
     * @notice Generates Koch curve points between two points
     */
    function _kochCurve(SVGLib.Point memory start, SVGLib.Point memory end, uint256 depth)
        internal
        pure
        returns (SVGLib.Point[] memory)
    {
        if (depth == 0) {
            SVGLib.Point[] memory result = new SVGLib.Point[](2);
            result[0] = start;
            result[1] = end;
            return result;
        }

        // Calculate the 5 points of Koch curve
        int256 dx = end.x - start.x;
        int256 dy = end.y - start.y;

        SVGLib.Point memory p1 = start;
        SVGLib.Point memory p2 = SVGLib.Point(start.x + dx / 3, start.y + dy / 3);
        SVGLib.Point memory p3 = SVGLib.Point(
            (start.x + end.x) / 2 - int256(int256(SQRT3_HALF) * dy / int256(PRECISION) / 3),
            (start.y + end.y) / 2 + int256(int256(SQRT3_HALF) * dx / int256(PRECISION) / 3)
        );
        SVGLib.Point memory p4 = SVGLib.Point(start.x + 2 * dx / 3, start.y + 2 * dy / 3);
        SVGLib.Point memory p5 = end;

        // Recurse on each segment
        SVGLib.Point[] memory seg1 = _kochCurve(p1, p2, depth - 1);
        SVGLib.Point[] memory seg2 = _kochCurve(p2, p3, depth - 1);
        SVGLib.Point[] memory seg3 = _kochCurve(p3, p4, depth - 1);
        SVGLib.Point[] memory seg4 = _kochCurve(p4, p5, depth - 1);

        // Combine segments
        uint256 totalLen = seg1.length + seg2.length + seg3.length + seg4.length - 3;
        SVGLib.Point[] memory result = new SVGLib.Point[](totalLen);

        uint256 idx = 0;
        for (uint256 i = 0; i < seg1.length - 1; i++) result[idx++] = seg1[i];
        for (uint256 i = 0; i < seg2.length - 1; i++) result[idx++] = seg2[i];
        for (uint256 i = 0; i < seg3.length - 1; i++) result[idx++] = seg3[i];
        for (uint256 i = 0; i < seg4.length; i++) result[idx++] = seg4[i];

        return result;
    }

    // ============ FRACTAL TREE ============

    /**
     * @notice Generates a fractal tree
     * @param config Tree configuration
     * @return SVG string of the tree
     */
    function fractalTree(TreeConfig memory config) internal pure returns (string memory) {
        uint256 depth = config.depth > 10 ? 10 : config.depth;
        return _treeRecursive(
            config.startX,
            config.startY,
            int256(config.trunkLength),
            900, // 90 degrees (pointing up) * 10
            depth,
            config.branchAngle,
            config.lengthRatio,
            config.colors,
            config.trunkLength / 10 // Initial stroke width
        );
    }

    /**
     * @notice Recursive helper for fractal tree
     */
    function _treeRecursive(
        int256 x,
        int256 y,
        int256 length,
        uint256 angle, // degrees * 10
        uint256 depth,
        uint256 branchAngle,
        uint256 lengthRatio,
        string[] memory colors,
        uint256 strokeWidth
    ) internal pure returns (string memory) {
        if (depth == 0 || length < 2) return "";

        // Calculate endpoint using trigonometry approximation
        int256 endX = x + (length * _cos(angle)) / int256(PRECISION);
        int256 endY = y - (length * _sin(angle)) / int256(PRECISION);

        // Get color for this depth
        string memory color = colors.length > 0 ? colors[depth % colors.length] : "8B4513";

        // Draw this branch
        string memory branch = SVGLib.line(SVGLib.Line(x, y, endX, endY), color, strokeWidth > 0 ? strokeWidth : 1);

        // Calculate new parameters
        int256 newLength = (length * int256(lengthRatio)) / int256(PRECISION);
        uint256 newStrokeWidth = strokeWidth > 1 ? strokeWidth - 1 : 1;

        // Recurse for left and right branches
        string memory leftBranch = _treeRecursive(
            endX, endY, newLength,
            angle + branchAngle,
            depth - 1, branchAngle, lengthRatio, colors, newStrokeWidth
        );

        string memory rightBranch = _treeRecursive(
            endX, endY, newLength,
            angle > branchAngle ? angle - branchAngle : 0,
            depth - 1, branchAngle, lengthRatio, colors, newStrokeWidth
        );

        return string(abi.encodePacked(branch, leftBranch, rightBranch));
    }

    // ============ GOLDEN SPIRAL ============

    /**
     * @notice Generates a golden spiral (Fibonacci spiral)
     * @param config Spiral configuration
     * @return SVG string of the spiral
     */
    function goldenSpiral(SpiralConfig memory config) internal pure returns (string memory) {
        uint256 totalPoints = config.turns * config.points;
        SVGLib.Point[] memory points = new SVGLib.Point[](totalPoints);

        uint256 radius = config.startRadius;

        for (uint256 i = 0; i < totalPoints; i++) {
            uint256 angle = (i * 3600) / config.points; // Angle in degrees * 10
            int256 x = config.centerX + int256((radius * uint256(_cos(angle))) / PRECISION);
            int256 y = config.centerY + int256((radius * uint256(_sin(angle))) / PRECISION);
            points[i] = SVGLib.Point(x, y);

            // Grow radius using golden ratio
            radius = (radius * config.growth) / PRECISION;
        }

        return SVGLib.polyline(points, config.strokeColor, config.strokeWidth);
    }

    // ============ CANTOR SET ============

    /**
     * @notice Generates a Cantor set fractal
     * @param config Cantor configuration
     * @return SVG string of the Cantor set
     */
    function cantorSet(CantorConfig memory config) internal pure returns (string memory) {
        uint256 depth = config.depth > 8 ? 8 : config.depth;
        return _cantorRecursive(config.startX, config.startY, config.width, depth, config.lineHeight, config.gapHeight, config.color);
    }

    /**
     * @notice Recursive helper for Cantor set
     */
    function _cantorRecursive(
        int256 x,
        int256 y,
        uint256 width,
        uint256 depth,
        uint256 lineHeight,
        uint256 gapHeight,
        string memory color
    ) internal pure returns (string memory) {
        // Draw current line
        string memory currentLine = SVGLib.rect(SVGLib.Rect(x, y, width, lineHeight), color, "", 0);

        if (depth == 0 || width < 3) return currentLine;

        // Calculate new parameters (remove middle third)
        uint256 newWidth = width / 3;
        int256 newY = y + int256(lineHeight + gapHeight);

        // Recurse for left and right thirds
        string memory leftSet = _cantorRecursive(x, newY, newWidth, depth - 1, lineHeight, gapHeight, color);
        string memory rightSet = _cantorRecursive(x + int256(2 * newWidth), newY, newWidth, depth - 1, lineHeight, gapHeight, color);

        return string(abi.encodePacked(currentLine, leftSet, rightSet));
    }

    // ============ VICSEK FRACTAL ============

    /**
     * @notice Generates a Vicsek fractal (cross-shaped)
     * @param size Square size
     * @param depth Recursion depth
     * @param fillColor Fill color
     * @param centerX Center X
     * @param centerY Center Y
     * @return SVG string of the Vicsek fractal
     */
    function vicsekFractal(
        uint256 size,
        uint256 depth,
        string memory fillColor,
        int256 centerX,
        int256 centerY
    ) internal pure returns (string memory) {
        uint256 clampedDepth = depth > 5 ? 5 : depth;
        int256 halfSize = int256(size / 2);
        return _vicsekRecursive(centerX - halfSize, centerY - halfSize, size, clampedDepth, fillColor);
    }

    /**
     * @notice Recursive helper for Vicsek fractal
     */
    function _vicsekRecursive(int256 x, int256 y, uint256 size, uint256 depth, string memory fill)
        internal
        pure
        returns (string memory)
    {
        if (depth == 0) {
            return SVGLib.rect(SVGLib.Rect(x, y, size, size), fill, "", 0);
        }

        uint256 newSize = size / 3;
        string memory result = "";

        // Generate cross pattern (center + 4 edges)
        // Top center
        result = string(abi.encodePacked(result, _vicsekRecursive(x + int256(newSize), y, newSize, depth - 1, fill)));
        // Middle left
        result = string(abi.encodePacked(result, _vicsekRecursive(x, y + int256(newSize), newSize, depth - 1, fill)));
        // Middle center
        result = string(abi.encodePacked(result, _vicsekRecursive(x + int256(newSize), y + int256(newSize), newSize, depth - 1, fill)));
        // Middle right
        result = string(abi.encodePacked(result, _vicsekRecursive(x + int256(2 * newSize), y + int256(newSize), newSize, depth - 1, fill)));
        // Bottom center
        result = string(abi.encodePacked(result, _vicsekRecursive(x + int256(newSize), y + int256(2 * newSize), newSize, depth - 1, fill)));

        return result;
    }

    // ============ HEXAGONAL FRACTAL ============

    /**
     * @notice Generates a hexagonal fractal pattern
     * @param size Hexagon size (radius)
     * @param depth Recursion depth
     * @param fillColor Fill color
     * @param strokeColor Stroke color
     * @param strokeWidth Stroke width
     * @param centerX Center X
     * @param centerY Center Y
     * @return SVG string of the hexagonal fractal
     */
    function hexagonalFractal(
        uint256 size,
        uint256 depth,
        string memory fillColor,
        string memory strokeColor,
        uint256 strokeWidth,
        int256 centerX,
        int256 centerY
    ) internal pure returns (string memory) {
        uint256 clampedDepth = depth > 5 ? 5 : depth;
        return _hexRecursive(centerX, centerY, size, clampedDepth, fillColor, strokeColor, strokeWidth);
    }

    /**
     * @notice Recursive helper for hexagonal fractal
     */
    function _hexRecursive(
        int256 cx,
        int256 cy,
        uint256 size,
        uint256 depth,
        string memory fill,
        string memory stroke,
        uint256 strokeWidth
    ) internal pure returns (string memory) {
        // Generate hexagon points
        SVGLib.Point[] memory points = new SVGLib.Point[](6);
        for (uint256 i = 0; i < 6; i++) {
            uint256 angle = 600 * i; // 60 degrees * i * 10
            points[i] = SVGLib.Point(
                cx + int256((size * uint256(_cos(angle))) / PRECISION),
                cy + int256((size * uint256(_sin(angle))) / PRECISION)
            );
        }

        string memory hexagon = SVGLib.polygon(points, fill, stroke, strokeWidth);

        if (depth == 0 || size < 10) return hexagon;

        // Generate 6 smaller hexagons at each vertex
        uint256 newSize = size / 3;
        string memory children = "";

        for (uint256 i = 0; i < 6; i++) {
            uint256 angle = 600 * i;
            int256 newCx = cx + int256((size * 2 / 3 * uint256(_cos(angle))) / PRECISION);
            int256 newCy = cy + int256((size * 2 / 3 * uint256(_sin(angle))) / PRECISION);
            children = string(abi.encodePacked(children, _hexRecursive(newCx, newCy, newSize, depth - 1, fill, stroke, strokeWidth)));
        }

        return string(abi.encodePacked(hexagon, children));
    }

    // ============ UTILITY FUNCTIONS ============

    /**
     * @notice Approximate sine function (angle in degrees * 10)
     * @param angle Angle in degrees * 10
     * @return Sine value * PRECISION
     */
    function _sin(uint256 angle) internal pure returns (int256) {
        // Normalize to 0-3600 (0-360 degrees)
        angle = angle % 3600;

        // Use lookup table approximation for key angles
        if (angle == 0) return 0;
        if (angle == 300) return 500; // sin(30) = 0.5
        if (angle == 450) return 707; // sin(45) ≈ 0.707
        if (angle == 600) return 866; // sin(60) ≈ 0.866
        if (angle == 900) return 1000; // sin(90) = 1
        if (angle == 1200) return 866;
        if (angle == 1350) return 707;
        if (angle == 1500) return 500;
        if (angle == 1800) return 0;
        if (angle == 2100) return -500;
        if (angle == 2250) return -707;
        if (angle == 2400) return -866;
        if (angle == 2700) return -1000;
        if (angle == 3000) return -866;
        if (angle == 3150) return -707;
        if (angle == 3300) return -500;

        // Linear interpolation for other angles
        uint256 segment = angle / 300;
        uint256 remainder = angle % 300;

        int256[13] memory sinTable = [int256(0), 500, 866, 1000, 866, 500, 0, -500, -866, -1000, -866, -500, 0];

        int256 start = sinTable[segment];
        int256 end = sinTable[(segment + 1) % 12];

        return start + ((end - start) * int256(remainder)) / 300;
    }

    /**
     * @notice Approximate cosine function (angle in degrees * 10)
     * @param angle Angle in degrees * 10
     * @return Cosine value * PRECISION
     */
    function _cos(uint256 angle) internal pure returns (int256) {
        return _sin(angle + 900); // cos(x) = sin(x + 90)
    }

    /**
     * @notice Generate deterministic pseudo-random value from seed
     * @param seed Random seed
     * @param index Index for variation
     * @return Random value 0-999
     */
    function pseudoRandom(uint256 seed, uint256 index) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(seed, index))) % 1000;
    }

    /**
     * @notice Generate random point within bounds
     * @param seed Random seed
     * @param index Index for variation
     * @param minX Minimum X
     * @param maxX Maximum X
     * @param minY Minimum Y
     * @param maxY Maximum Y
     * @return Random point
     */
    function randomPoint(uint256 seed, uint256 index, int256 minX, int256 maxX, int256 minY, int256 maxY)
        internal
        pure
        returns (SVGLib.Point memory)
    {
        uint256 randX = pseudoRandom(seed, index * 2);
        uint256 randY = pseudoRandom(seed, index * 2 + 1);

        int256 x = minX + int256((randX * uint256(maxX - minX)) / 1000);
        int256 y = minY + int256((randY * uint256(maxY - minY)) / 1000);

        return SVGLib.Point(x, y);
    }

    /**
     * @notice Calculate distance between two points
     * @param p1 First point
     * @param p2 Second point
     * @return Distance * PRECISION
     */
    function distance(SVGLib.Point memory p1, SVGLib.Point memory p2) internal pure returns (uint256) {
        int256 dx = p2.x - p1.x;
        int256 dy = p2.y - p1.y;
        return sqrt(uint256(dx * dx + dy * dy));
    }

    /**
     * @notice Integer square root (Babylonian method)
     * @param x Input value
     * @return Square root
     */
    function sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;

        uint256 z = (x + 1) / 2;
        uint256 y = x;

        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }

        return y;
    }

    /**
     * @notice Linear interpolation between two values
     * @param a Start value
     * @param b End value
     * @param t Interpolation factor (0-1000)
     * @return Interpolated value
     */
    function lerp(int256 a, int256 b, uint256 t) internal pure returns (int256) {
        return a + ((b - a) * int256(t)) / int256(PRECISION);
    }

    /**
     * @notice Interpolate between two points
     * @param p1 Start point
     * @param p2 End point
     * @param t Interpolation factor (0-1000)
     * @return Interpolated point
     */
    function lerpPoint(SVGLib.Point memory p1, SVGLib.Point memory p2, uint256 t)
        internal
        pure
        returns (SVGLib.Point memory)
    {
        return SVGLib.Point(lerp(p1.x, p2.x, t), lerp(p1.y, p2.y, t));
    }
}
