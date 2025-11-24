// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title VisualLib
 * @notice Visual effects and pattern generation for on-chain generative art
 * @dev Provides noise functions, patterns, particle systems, and procedural visuals
 */
library VisualLib {
    // ============ CONSTANTS ============

    /// @notice Fixed-point precision (1000 = 1.0)
    uint256 internal constant PRECISION = 1000;

    /// @notice Grid size for noise generation
    uint256 internal constant NOISE_GRID = 256;

    /// @notice Pi approximation scaled by 1000
    uint256 internal constant PI_SCALED = 3142;

    // ============ TYPES ============

    /// @notice 2D point
    struct Point {
        int256 x;
        int256 y;
    }

    /// @notice Particle definition
    struct Particle {
        int256 x;
        int256 y;
        int256 vx;          // Velocity X
        int256 vy;          // Velocity Y
        uint256 size;
        uint256 life;       // Remaining life (0-1000)
        uint256 color;      // Packed RGB
    }

    /// @notice Particle system configuration
    struct ParticleConfig {
        uint256 count;          // Number of particles
        uint256 minSize;        // Minimum particle size
        uint256 maxSize;        // Maximum particle size
        uint256 speed;          // Base speed
        uint256 spread;         // Spawn spread
        uint256 gravity;        // Gravity strength
        uint256 friction;       // Friction coefficient (0-1000)
        bool fadeOut;           // Whether particles fade
    }

    /// @notice Pattern configuration
    struct PatternConfig {
        uint256 scale;          // Pattern scale
        uint256 density;        // Pattern density
        uint256 rotation;       // Rotation in degrees
        uint256 seed;           // Random seed
    }

    /// @notice Gradient stop
    struct GradientStop {
        uint256 position;       // Position (0-1000)
        uint8 r;
        uint8 g;
        uint8 b;
    }

    /// @notice Flow field cell
    struct FlowCell {
        int256 angle;           // Direction angle (degrees * 10)
        uint256 magnitude;      // Flow strength
    }

    // ============ NOISE FUNCTIONS ============

    /**
     * @notice Generate Perlin-like noise value
     * @param x X coordinate
     * @param y Y coordinate
     * @param seed Random seed
     * @return Noise value (0-1000)
     */
    function noise2D(int256 x, int256 y, uint256 seed) internal pure returns (uint256) {
        // Grid cell coordinates
        int256 x0 = x >= 0 ? x / int256(NOISE_GRID) : (x - int256(NOISE_GRID) + 1) / int256(NOISE_GRID);
        int256 y0 = y >= 0 ? y / int256(NOISE_GRID) : (y - int256(NOISE_GRID) + 1) / int256(NOISE_GRID);
        int256 x1 = x0 + 1;
        int256 y1 = y0 + 1;

        // Local coordinates within cell
        uint256 sx = uint256(x >= 0 ? x % int256(NOISE_GRID) : int256(NOISE_GRID) + (x % int256(NOISE_GRID)));
        uint256 sy = uint256(y >= 0 ? y % int256(NOISE_GRID) : int256(NOISE_GRID) + (y % int256(NOISE_GRID)));

        // Corner gradients
        uint256 n00 = _gradientDot(x0, y0, sx, sy, seed);
        uint256 n01 = _gradientDot(x0, y1, sx, NOISE_GRID - sy, seed);
        uint256 n10 = _gradientDot(x1, y0, NOISE_GRID - sx, sy, seed);
        uint256 n11 = _gradientDot(x1, y1, NOISE_GRID - sx, NOISE_GRID - sy, seed);

        // Smooth interpolation
        uint256 tx = _smoothstep(sx * PRECISION / NOISE_GRID);
        uint256 ty = _smoothstep(sy * PRECISION / NOISE_GRID);

        // Bilinear interpolation
        uint256 nx0 = _lerp(n00, n10, tx);
        uint256 nx1 = _lerp(n01, n11, tx);

        return _lerp(nx0, nx1, ty);
    }

    /**
     * @notice Generate fractal noise (multiple octaves)
     * @param x X coordinate
     * @param y Y coordinate
     * @param octaves Number of noise layers
     * @param persistence Amplitude decay per octave (0-1000)
     * @param seed Random seed
     * @return Fractal noise value (0-1000)
     */
    function fractalNoise(
        int256 x,
        int256 y,
        uint256 octaves,
        uint256 persistence,
        uint256 seed
    ) internal pure returns (uint256) {
        uint256 total = 0;
        uint256 amplitude = PRECISION;
        uint256 maxValue = 0;
        int256 frequency = 1;

        for (uint256 i = 0; i < octaves; i++) {
            total += noise2D(x * frequency, y * frequency, seed + i) * amplitude / PRECISION;
            maxValue += amplitude;
            amplitude = (amplitude * persistence) / PRECISION;
            frequency *= 2;
        }

        return (total * PRECISION) / maxValue;
    }

    /**
     * @notice Generate turbulence noise
     * @param x X coordinate
     * @param y Y coordinate
     * @param octaves Number of octaves
     * @param seed Random seed
     * @return Turbulence value (0-1000)
     */
    function turbulence(int256 x, int256 y, uint256 octaves, uint256 seed) internal pure returns (uint256) {
        uint256 total = 0;
        int256 freq = 1;
        uint256 amp = PRECISION;

        for (uint256 i = 0; i < octaves; i++) {
            uint256 n = noise2D(x * freq, y * freq, seed + i);
            // Take absolute value from center
            total += n > 500 ? (n - 500) * 2 * amp / PRECISION : (500 - n) * 2 * amp / PRECISION;
            freq *= 2;
            amp /= 2;
        }

        return total > PRECISION ? PRECISION : total;
    }

    /**
     * @notice Generate worley/cellular noise
     * @param x X coordinate
     * @param y Y coordinate
     * @param cellSize Size of cells
     * @param seed Random seed
     * @return Distance to nearest cell point (0-1000)
     */
    function worleyNoise(int256 x, int256 y, uint256 cellSize, uint256 seed) internal pure returns (uint256) {
        int256 cellX = x / int256(cellSize);
        int256 cellY = y / int256(cellSize);

        uint256 minDist = type(uint256).max;

        // Check 3x3 grid of cells
        for (int256 i = -1; i <= 1; i++) {
            for (int256 j = -1; j <= 1; j++) {
                // Random point in cell
                uint256 hash = uint256(keccak256(abi.encodePacked(cellX + i, cellY + j, seed)));
                int256 px = (cellX + i) * int256(cellSize) + int256((hash % cellSize));
                int256 py = (cellY + j) * int256(cellSize) + int256(((hash >> 8) % cellSize));

                // Distance
                uint256 dist = _distance(x, y, px, py);
                if (dist < minDist) {
                    minDist = dist;
                }
            }
        }

        // Normalize to 0-1000
        return (minDist * PRECISION) / cellSize;
    }

    // ============ PATTERNS ============

    /**
     * @notice Generate checkerboard pattern
     * @param x X coordinate
     * @param y Y coordinate
     * @param size Square size
     * @return 0 or 1000 (black or white)
     */
    function checkerboard(int256 x, int256 y, uint256 size) internal pure returns (uint256) {
        int256 cx = x >= 0 ? x / int256(size) : (x - int256(size) + 1) / int256(size);
        int256 cy = y >= 0 ? y / int256(size) : (y - int256(size) + 1) / int256(size);
        return ((cx + cy) % 2 == 0) ? PRECISION : 0;
    }

    /**
     * @notice Generate stripe pattern
     * @param x X coordinate
     * @param y Y coordinate
     * @param width Stripe width
     * @param angle Angle in degrees
     * @return 0 or 1000
     */
    function stripes(int256 x, int256 y, uint256 width, uint256 angle) internal pure returns (uint256) {
        // Rotate coordinates
        int256 rx = (x * int256(_cos(angle)) - y * int256(_sin(angle))) / int256(PRECISION);

        int256 stripe = rx >= 0 ? rx / int256(width) : (rx - int256(width) + 1) / int256(width);
        return (stripe % 2 == 0) ? PRECISION : 0;
    }

    /**
     * @notice Generate dot grid pattern
     * @param x X coordinate
     * @param y Y coordinate
     * @param spacing Dot spacing
     * @param radius Dot radius
     * @return Intensity (0-1000)
     */
    function dotGrid(int256 x, int256 y, uint256 spacing, uint256 radius) internal pure returns (uint256) {
        // Find nearest grid point
        int256 gx = ((x + int256(spacing / 2)) / int256(spacing)) * int256(spacing);
        int256 gy = ((y + int256(spacing / 2)) / int256(spacing)) * int256(spacing);

        uint256 dist = _distance(x, y, gx, gy);

        if (dist <= radius) {
            return PRECISION;
        } else if (dist <= radius * 2) {
            return PRECISION - ((dist - radius) * PRECISION / radius);
        }
        return 0;
    }

    /**
     * @notice Generate concentric circles pattern
     * @param x X coordinate (relative to center)
     * @param y Y coordinate (relative to center)
     * @param spacing Ring spacing
     * @param thickness Ring thickness
     * @return Intensity (0-1000)
     */
    function concentricCircles(int256 x, int256 y, uint256 spacing, uint256 thickness) internal pure returns (uint256) {
        uint256 dist = _sqrt(uint256(x * x + y * y));
        uint256 ring = dist % spacing;

        if (ring <= thickness / 2 || ring >= spacing - thickness / 2) {
            return PRECISION;
        }
        return 0;
    }

    /**
     * @notice Generate wave pattern
     * @param x X coordinate
     * @param y Y coordinate
     * @param wavelength Wave length
     * @param amplitude Wave amplitude
     * @param phase Phase offset
     * @return Y offset value
     */
    function wave(int256 x, uint256 wavelength, uint256 amplitude, uint256 phase) internal pure returns (int256) {
        uint256 angle = ((uint256(x >= 0 ? x : -x) + phase) * 3600) / wavelength;
        return int256((amplitude * _sin(angle % 3600)) / PRECISION);
    }

    /**
     * @notice Generate hexagonal grid pattern
     * @param x X coordinate
     * @param y Y coordinate
     * @param size Hexagon size
     * @return Distance from hex center (0-1000)
     */
    function hexGrid(int256 x, int256 y, uint256 size) internal pure returns (uint256) {
        // Convert to hex coordinates
        uint256 hexWidth = size * 2;
        uint256 hexHeight = (size * 1732) / 1000; // sqrt(3) * size

        int256 row = y / int256(hexHeight);
        int256 col;

        if (row % 2 == 0) {
            col = x / int256(hexWidth);
        } else {
            col = (x - int256(size)) / int256(hexWidth);
        }

        // Center of nearest hex
        int256 cx = col * int256(hexWidth) + (row % 2 == 0 ? 0 : int256(size));
        int256 cy = row * int256(hexHeight);

        uint256 dist = _distance(x, y, cx, cy);
        return dist < size ? (dist * PRECISION / size) : PRECISION;
    }

    // ============ FLOW FIELDS ============

    /**
     * @notice Generate flow field from noise
     * @param x X coordinate
     * @param y Y coordinate
     * @param scale Noise scale
     * @param seed Random seed
     * @return Flow cell with direction and magnitude
     */
    function flowField(int256 x, int256 y, uint256 scale, uint256 seed) internal pure returns (FlowCell memory) {
        uint256 n = noise2D(x / int256(scale), y / int256(scale), seed);

        // Convert noise to angle (0-3600 = 0-360 degrees * 10)
        int256 angle = int256((n * 3600) / PRECISION);

        // Use second noise sample for magnitude
        uint256 mag = noise2D(x / int256(scale) + 1000, y / int256(scale) + 1000, seed + 1);

        return FlowCell({
            angle: angle,
            magnitude: mag
        });
    }

    /**
     * @notice Get velocity from flow field
     * @param cell Flow field cell
     * @return vx X velocity component
     * @return vy Y velocity component
     */
    function flowVelocity(FlowCell memory cell) internal pure returns (int256 vx, int256 vy) {
        vx = int256((_cos(uint256(cell.angle >= 0 ? cell.angle : -cell.angle) / 10) * cell.magnitude) / PRECISION);
        vy = int256((_sin(uint256(cell.angle >= 0 ? cell.angle : -cell.angle) / 10) * cell.magnitude) / PRECISION);

        if (cell.angle < 0) {
            vy = -vy;
        }
    }

    // ============ PARTICLE SYSTEMS ============

    /**
     * @notice Initialize particles for a system
     * @param config Particle configuration
     * @param centerX Center X position
     * @param centerY Center Y position
     * @param seed Random seed
     * @return particles Array of initialized particles
     */
    function initParticles(
        ParticleConfig memory config,
        int256 centerX,
        int256 centerY,
        uint256 seed
    ) internal pure returns (Particle[] memory particles) {
        particles = new Particle[](config.count);

        for (uint256 i = 0; i < config.count; i++) {
            uint256 hash = uint256(keccak256(abi.encodePacked(seed, i)));

            // Random position within spread
            int256 px = centerX + int256((hash % (config.spread * 2)) - config.spread);
            int256 py = centerY + int256(((hash >> 16) % (config.spread * 2)) - config.spread);

            // Random velocity
            int256 angle = int256((hash >> 32) % 3600);
            int256 speed = int256(config.speed + ((hash >> 48) % config.speed));

            particles[i] = Particle({
                x: px,
                y: py,
                vx: (speed * int256(_cos(uint256(angle) / 10))) / int256(PRECISION),
                vy: (speed * int256(_sin(uint256(angle) / 10))) / int256(PRECISION),
                size: config.minSize + ((hash >> 64) % (config.maxSize - config.minSize + 1)),
                life: PRECISION,
                color: hash >> 80
            });
        }
    }

    /**
     * @notice Update particle positions
     * @param particles Array of particles
     * @param config Particle configuration
     * @param deltaTime Time step (in arbitrary units)
     * @return Updated particles
     */
    function updateParticles(
        Particle[] memory particles,
        ParticleConfig memory config,
        uint256 deltaTime
    ) internal pure returns (Particle[] memory) {
        for (uint256 i = 0; i < particles.length; i++) {
            if (particles[i].life == 0) continue;

            // Apply velocity
            particles[i].x += (particles[i].vx * int256(deltaTime)) / int256(PRECISION);
            particles[i].y += (particles[i].vy * int256(deltaTime)) / int256(PRECISION);

            // Apply gravity
            particles[i].vy += int256((config.gravity * deltaTime) / PRECISION);

            // Apply friction
            particles[i].vx = (particles[i].vx * int256(config.friction)) / int256(PRECISION);
            particles[i].vy = (particles[i].vy * int256(config.friction)) / int256(PRECISION);

            // Decay life
            if (config.fadeOut && particles[i].life > deltaTime) {
                particles[i].life -= deltaTime;
            } else if (config.fadeOut) {
                particles[i].life = 0;
            }
        }

        return particles;
    }

    // ============ GRADIENTS ============

    /**
     * @notice Sample linear gradient
     * @param position Position along gradient (0-1000)
     * @param stops Array of gradient stops (must be sorted by position)
     * @return r Red component
     * @return g Green component
     * @return b Blue component
     */
    function sampleGradient(uint256 position, GradientStop[] memory stops)
        internal
        pure
        returns (uint8 r, uint8 g, uint8 b)
    {
        if (stops.length == 0) return (0, 0, 0);
        if (stops.length == 1) return (stops[0].r, stops[0].g, stops[0].b);

        // Find surrounding stops
        uint256 nextIdx = 0;
        for (uint256 i = 0; i < stops.length; i++) {
            if (stops[i].position > position) {
                nextIdx = i;
                break;
            }
            if (i == stops.length - 1) {
                return (stops[i].r, stops[i].g, stops[i].b);
            }
        }

        if (nextIdx == 0) return (stops[0].r, stops[0].g, stops[0].b);

        GradientStop memory prev = stops[nextIdx - 1];
        GradientStop memory next = stops[nextIdx];

        // Interpolation factor
        uint256 t = ((position - prev.position) * PRECISION) / (next.position - prev.position);

        r = uint8(_lerp(prev.r, next.r, t));
        g = uint8(_lerp(prev.g, next.g, t));
        b = uint8(_lerp(prev.b, next.b, t));
    }

    /**
     * @notice Create radial gradient sample
     * @param x X coordinate (relative to center)
     * @param y Y coordinate (relative to center)
     * @param radius Gradient radius
     * @param stops Gradient stops
     * @return r Red component
     * @return g Green component
     * @return b Blue component
     */
    function sampleRadialGradient(
        int256 x,
        int256 y,
        uint256 radius,
        GradientStop[] memory stops
    ) internal pure returns (uint8 r, uint8 g, uint8 b) {
        uint256 dist = _sqrt(uint256(x * x + y * y));
        uint256 position = (dist * PRECISION) / radius;
        if (position > PRECISION) position = PRECISION;

        return sampleGradient(position, stops);
    }

    // ============ BLEND MODES ============

    /**
     * @notice Multiply blend mode
     * @param base Base value (0-255)
     * @param blend Blend value (0-255)
     * @return Blended value
     */
    function blendMultiply(uint8 base, uint8 blend) internal pure returns (uint8) {
        return uint8((uint256(base) * uint256(blend)) / 255);
    }

    /**
     * @notice Screen blend mode
     * @param base Base value (0-255)
     * @param blend Blend value (0-255)
     * @return Blended value
     */
    function blendScreen(uint8 base, uint8 blend) internal pure returns (uint8) {
        return uint8(255 - ((255 - uint256(base)) * (255 - uint256(blend))) / 255);
    }

    /**
     * @notice Overlay blend mode
     * @param base Base value (0-255)
     * @param blend Blend value (0-255)
     * @return Blended value
     */
    function blendOverlay(uint8 base, uint8 blend) internal pure returns (uint8) {
        if (base < 128) {
            return uint8((2 * uint256(base) * uint256(blend)) / 255);
        }
        return uint8(255 - (2 * (255 - uint256(base)) * (255 - uint256(blend))) / 255);
    }

    /**
     * @notice Soft light blend mode
     * @param base Base value (0-255)
     * @param blend Blend value (0-255)
     * @return Blended value
     */
    function blendSoftLight(uint8 base, uint8 blend) internal pure returns (uint8) {
        if (blend < 128) {
            return uint8(uint256(base) - ((255 - 2 * uint256(blend)) * uint256(base) * (255 - uint256(base))) / (255 * 255));
        }
        uint256 d = base < 64
            ? ((16 * uint256(base) - 12 * 255) * uint256(base) + 4 * 255 * 255) * uint256(base) / (255 * 255 * 255)
            : _sqrt(uint256(base) * 255);
        return uint8(uint256(base) + (2 * uint256(blend) - 255) * (d - uint256(base)) / 255);
    }

    // ============ INTERNAL HELPERS ============

    /**
     * @notice Gradient dot product for noise
     */
    function _gradientDot(int256 gx, int256 gy, uint256 dx, uint256 dy, uint256 seed) internal pure returns (uint256) {
        uint256 hash = uint256(keccak256(abi.encodePacked(gx, gy, seed)));
        uint256 gradIdx = hash % 4;

        int256 gdx;
        int256 gdy;

        if (gradIdx == 0) { gdx = 1; gdy = 1; }
        else if (gradIdx == 1) { gdx = -1; gdy = 1; }
        else if (gradIdx == 2) { gdx = 1; gdy = -1; }
        else { gdx = -1; gdy = -1; }

        int256 dot = gdx * int256(dx) + gdy * int256(dy);

        // Normalize to 0-1000
        return uint256((dot + int256(NOISE_GRID * 2)) * int256(PRECISION) / int256(NOISE_GRID * 4));
    }

    /**
     * @notice Smoothstep interpolation
     */
    function _smoothstep(uint256 t) internal pure returns (uint256) {
        // 3t^2 - 2t^3
        uint256 t2 = (t * t) / PRECISION;
        uint256 t3 = (t2 * t) / PRECISION;
        return (3 * t2) - (2 * t3);
    }

    /**
     * @notice Linear interpolation
     */
    function _lerp(uint256 a, uint256 b, uint256 t) internal pure returns (uint256) {
        if (t == 0) return a;
        if (t >= PRECISION) return b;
        if (b >= a) {
            return a + ((b - a) * t) / PRECISION;
        }
        return a - ((a - b) * t) / PRECISION;
    }

    /**
     * @notice Distance between two points
     */
    function _distance(int256 x1, int256 y1, int256 x2, int256 y2) internal pure returns (uint256) {
        int256 dx = x2 - x1;
        int256 dy = y2 - y1;
        return _sqrt(uint256(dx * dx + dy * dy));
    }

    /**
     * @notice Integer square root
     */
    function _sqrt(uint256 x) internal pure returns (uint256) {
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
     * @notice Approximate cosine (input: degrees)
     */
    function _cos(uint256 angle) internal pure returns (uint256) {
        angle = angle % 360;

        if (angle <= 90) {
            return PRECISION - (angle * angle * PRECISION) / (90 * 90 * 2);
        } else if (angle <= 180) {
            uint256 adj = angle - 90;
            return (adj * adj * PRECISION) / (90 * 90 * 2);
        } else if (angle <= 270) {
            uint256 adj = angle - 180;
            return PRECISION - (adj * adj * PRECISION) / (90 * 90 * 2);
        } else {
            uint256 adj = 360 - angle;
            return PRECISION - (adj * adj * PRECISION) / (90 * 90 * 2);
        }
    }

    /**
     * @notice Approximate sine (input: degrees)
     */
    function _sin(uint256 angle) internal pure returns (uint256) {
        return _cos((270 + 360 - angle) % 360);
    }
}
