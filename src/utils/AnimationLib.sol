// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title AnimationLib
 * @notice On-chain SVG animation utilities
 * @dev Provides easing functions, keyframe generation, and SVG animate elements
 *      for creating dynamic on-chain NFT artwork
 */
library AnimationLib {
    // ============ CONSTANTS ============

    /// @notice Fixed-point precision (1000 = 1.0)
    uint256 internal constant PRECISION = 1000;

    /// @notice Pi approximation scaled by 1000
    uint256 internal constant PI_SCALED = 3142;

    /// @notice Common animation durations in milliseconds
    uint256 internal constant DURATION_FAST = 200;
    uint256 internal constant DURATION_NORMAL = 500;
    uint256 internal constant DURATION_SLOW = 1000;

    // ============ TYPES ============

    /// @notice Keyframe definition
    struct Keyframe {
        uint256 time;         // Time offset (0-1000 = 0%-100%)
        int256 value;         // Value at this keyframe
        EasingType easing;    // Easing to next keyframe
    }

    /// @notice Animation configuration
    struct AnimationConfig {
        uint256 duration;        // Duration in milliseconds
        uint256 delay;           // Start delay in milliseconds
        uint256 iterations;      // Number of iterations (0 = infinite)
        bool alternate;          // Alternate direction each iteration
        FillMode fillMode;       // Behavior before/after animation
    }

    /// @notice Easing function types
    enum EasingType {
        Linear,
        EaseIn,
        EaseOut,
        EaseInOut,
        EaseInQuad,
        EaseOutQuad,
        EaseInOutQuad,
        EaseInCubic,
        EaseOutCubic,
        EaseInOutCubic,
        EaseInElastic,
        EaseOutElastic,
        EaseInBounce,
        EaseOutBounce,
        EaseInBack,
        EaseOutBack,
        Step
    }

    /// @notice Animation fill mode
    enum FillMode {
        None,
        Forwards,
        Backwards,
        Both
    }

    /// @notice Transform animation type
    enum TransformType {
        Translate,
        TranslateX,
        TranslateY,
        Scale,
        ScaleX,
        ScaleY,
        Rotate,
        SkewX,
        SkewY
    }

    // ============ EASING FUNCTIONS ============

    /**
     * @notice Apply easing function to progress value
     * @param progress Progress value (0-1000)
     * @param easing Easing type to apply
     * @return Eased progress value
     */
    function ease(uint256 progress, EasingType easing) internal pure returns (uint256) {
        if (progress == 0) return 0;
        if (progress >= PRECISION) return PRECISION;

        if (easing == EasingType.Linear) {
            return progress;
        } else if (easing == EasingType.EaseIn) {
            return easeInSine(progress);
        } else if (easing == EasingType.EaseOut) {
            return easeOutSine(progress);
        } else if (easing == EasingType.EaseInOut) {
            return easeInOutSine(progress);
        } else if (easing == EasingType.EaseInQuad) {
            return easeInQuad(progress);
        } else if (easing == EasingType.EaseOutQuad) {
            return easeOutQuad(progress);
        } else if (easing == EasingType.EaseInOutQuad) {
            return easeInOutQuad(progress);
        } else if (easing == EasingType.EaseInCubic) {
            return easeInCubic(progress);
        } else if (easing == EasingType.EaseOutCubic) {
            return easeOutCubic(progress);
        } else if (easing == EasingType.EaseInOutCubic) {
            return easeInOutCubic(progress);
        } else if (easing == EasingType.EaseInElastic) {
            return easeInElastic(progress);
        } else if (easing == EasingType.EaseOutElastic) {
            return easeOutElastic(progress);
        } else if (easing == EasingType.EaseInBounce) {
            return easeInBounce(progress);
        } else if (easing == EasingType.EaseOutBounce) {
            return easeOutBounce(progress);
        } else if (easing == EasingType.EaseInBack) {
            return easeInBack(progress);
        } else if (easing == EasingType.EaseOutBack) {
            return easeOutBack(progress);
        } else if (easing == EasingType.Step) {
            return progress >= 500 ? PRECISION : 0;
        }

        return progress;
    }

    /**
     * @notice Quadratic ease-in
     */
    function easeInQuad(uint256 t) internal pure returns (uint256) {
        return (t * t) / PRECISION;
    }

    /**
     * @notice Quadratic ease-out
     */
    function easeOutQuad(uint256 t) internal pure returns (uint256) {
        return PRECISION - ((PRECISION - t) * (PRECISION - t)) / PRECISION;
    }

    /**
     * @notice Quadratic ease-in-out
     */
    function easeInOutQuad(uint256 t) internal pure returns (uint256) {
        if (t < 500) {
            return (2 * t * t) / PRECISION;
        }
        uint256 t2 = t - 500;
        return 500 + (PRECISION - (2 * (500 - t2) * (500 - t2)) / PRECISION) / 2;
    }

    /**
     * @notice Cubic ease-in
     */
    function easeInCubic(uint256 t) internal pure returns (uint256) {
        return (t * t * t) / (PRECISION * PRECISION);
    }

    /**
     * @notice Cubic ease-out
     */
    function easeOutCubic(uint256 t) internal pure returns (uint256) {
        uint256 inv = PRECISION - t;
        return PRECISION - (inv * inv * inv) / (PRECISION * PRECISION);
    }

    /**
     * @notice Cubic ease-in-out
     */
    function easeInOutCubic(uint256 t) internal pure returns (uint256) {
        if (t < 500) {
            return (4 * t * t * t) / (PRECISION * PRECISION);
        }
        uint256 f = 2 * t - PRECISION;
        return 500 + (PRECISION - (4 * (PRECISION - f) * (PRECISION - f) * (PRECISION - f)) / (PRECISION * PRECISION)) / 2;
    }

    /**
     * @notice Sine ease-in
     */
    function easeInSine(uint256 t) internal pure returns (uint256) {
        return PRECISION - _cos((t * 900) / PRECISION);
    }

    /**
     * @notice Sine ease-out
     */
    function easeOutSine(uint256 t) internal pure returns (uint256) {
        return _sin((t * 900) / PRECISION);
    }

    /**
     * @notice Sine ease-in-out
     */
    function easeInOutSine(uint256 t) internal pure returns (uint256) {
        return (PRECISION - _cos((t * 1800) / PRECISION)) / 2;
    }

    /**
     * @notice Elastic ease-in
     */
    function easeInElastic(uint256 t) internal pure returns (uint256) {
        if (t == 0) return 0;
        if (t >= PRECISION) return PRECISION;

        // Simplified elastic: sin wave with exponential growth
        uint256 wave = _sin((t * 3 * 3600) / PRECISION);
        uint256 growth = (t * t) / PRECISION;
        return (wave * growth) / PRECISION;
    }

    /**
     * @notice Elastic ease-out
     */
    function easeOutElastic(uint256 t) internal pure returns (uint256) {
        if (t == 0) return 0;
        if (t >= PRECISION) return PRECISION;

        return PRECISION - easeInElastic(PRECISION - t);
    }

    /**
     * @notice Bounce ease-in
     */
    function easeInBounce(uint256 t) internal pure returns (uint256) {
        return PRECISION - easeOutBounce(PRECISION - t);
    }

    /**
     * @notice Bounce ease-out
     */
    function easeOutBounce(uint256 t) internal pure returns (uint256) {
        uint256 n1 = 7563; // 7.5625 * 1000
        uint256 d1 = 2727; // 2.727... * 1000

        if (t < 363) { // 1/2.75
            return (n1 * t * t) / (PRECISION * PRECISION * PRECISION);
        } else if (t < 727) { // 2/2.75
            t = t - 545; // t - 1.5/2.75
            return (n1 * t * t) / (PRECISION * PRECISION * PRECISION) + 750;
        } else if (t < 909) { // 2.5/2.75
            t = t - 818; // t - 2.25/2.75
            return (n1 * t * t) / (PRECISION * PRECISION * PRECISION) + 938;
        } else {
            t = t - 955; // t - 2.625/2.75
            return (n1 * t * t) / (PRECISION * PRECISION * PRECISION) + 984;
        }
    }

    /**
     * @notice Back ease-in (overshoots then returns)
     */
    function easeInBack(uint256 t) internal pure returns (uint256) {
        uint256 c1 = 1701; // 1.70158 * 1000
        uint256 c3 = 2701; // c1 + 1

        uint256 t2 = (t * t) / PRECISION;
        uint256 t3 = (t2 * t) / PRECISION;

        if (t3 * c3 / PRECISION > t2 * c1 / PRECISION) {
            return (t3 * c3 - t2 * c1) / PRECISION;
        }
        return 0;
    }

    /**
     * @notice Back ease-out
     */
    function easeOutBack(uint256 t) internal pure returns (uint256) {
        return PRECISION - easeInBack(PRECISION - t);
    }

    // ============ SVG ANIMATE ELEMENTS ============

    /**
     * @notice Create SVG animate element for attribute animation
     * @param attribute Attribute name to animate
     * @param from Start value
     * @param to End value
     * @param config Animation configuration
     * @return SVG animate element string
     */
    function animate(
        string memory attribute,
        string memory from,
        string memory to,
        AnimationConfig memory config
    ) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                '<animate attributeName="', attribute, '" ',
                'from="', from, '" ',
                'to="', to, '" ',
                _buildAnimationAttrs(config),
                '/>'
            )
        );
    }

    /**
     * @notice Create animate element with keyframe values
     * @param attribute Attribute name
     * @param values Semicolon-separated values
     * @param keyTimes Semicolon-separated times (0-1)
     * @param config Animation configuration
     * @return SVG animate element with keyframes
     */
    function animateKeyframes(
        string memory attribute,
        string memory values,
        string memory keyTimes,
        AnimationConfig memory config
    ) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                '<animate attributeName="', attribute, '" ',
                'values="', values, '" ',
                'keyTimes="', keyTimes, '" ',
                _buildAnimationAttrs(config),
                '/>'
            )
        );
    }

    /**
     * @notice Create animateTransform element
     * @param transformType Type of transform (translate, scale, rotate)
     * @param from Start transform value
     * @param to End transform value
     * @param config Animation configuration
     * @return SVG animateTransform element
     */
    function animateTransform(
        string memory transformType,
        string memory from,
        string memory to,
        AnimationConfig memory config
    ) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                '<animateTransform attributeName="transform" ',
                'type="', transformType, '" ',
                'from="', from, '" ',
                'to="', to, '" ',
                _buildAnimationAttrs(config),
                '/>'
            )
        );
    }

    /**
     * @notice Create rotation animation
     * @param fromDegrees Start angle
     * @param toDegrees End angle
     * @param cx Center X
     * @param cy Center Y
     * @param config Animation configuration
     * @return SVG animateTransform for rotation
     */
    function animateRotation(
        int256 fromDegrees,
        int256 toDegrees,
        int256 cx,
        int256 cy,
        AnimationConfig memory config
    ) internal pure returns (string memory) {
        string memory from = string(
            abi.encodePacked(_intToString(fromDegrees), " ", _intToString(cx), " ", _intToString(cy))
        );
        string memory to = string(
            abi.encodePacked(_intToString(toDegrees), " ", _intToString(cx), " ", _intToString(cy))
        );

        return animateTransform("rotate", from, to, config);
    }

    /**
     * @notice Create scale animation
     * @param fromScale Start scale (1000 = 1.0)
     * @param toScale End scale
     * @param config Animation configuration
     * @return SVG animateTransform for scale
     */
    function animateScale(
        uint256 fromScale,
        uint256 toScale,
        AnimationConfig memory config
    ) internal pure returns (string memory) {
        string memory from = _decimalToString(fromScale, 3);
        string memory to = _decimalToString(toScale, 3);

        return animateTransform("scale", from, to, config);
    }

    /**
     * @notice Create translation animation
     * @param fromX Start X
     * @param fromY Start Y
     * @param toX End X
     * @param toY End Y
     * @param config Animation configuration
     * @return SVG animateTransform for translation
     */
    function animateTranslation(
        int256 fromX,
        int256 fromY,
        int256 toX,
        int256 toY,
        AnimationConfig memory config
    ) internal pure returns (string memory) {
        string memory from = string(abi.encodePacked(_intToString(fromX), " ", _intToString(fromY)));
        string memory to = string(abi.encodePacked(_intToString(toX), " ", _intToString(toY)));

        return animateTransform("translate", from, to, config);
    }

    /**
     * @notice Create color animation
     * @param attribute Color attribute (fill, stroke)
     * @param fromColor Start color (hex)
     * @param toColor End color (hex)
     * @param config Animation configuration
     * @return SVG animate for color
     */
    function animateColor(
        string memory attribute,
        string memory fromColor,
        string memory toColor,
        AnimationConfig memory config
    ) internal pure returns (string memory) {
        return animate(
            attribute,
            string(abi.encodePacked("#", fromColor)),
            string(abi.encodePacked("#", toColor)),
            config
        );
    }

    /**
     * @notice Create opacity animation
     * @param fromOpacity Start opacity (0-1000)
     * @param toOpacity End opacity (0-1000)
     * @param config Animation configuration
     * @return SVG animate for opacity
     */
    function animateOpacity(
        uint256 fromOpacity,
        uint256 toOpacity,
        AnimationConfig memory config
    ) internal pure returns (string memory) {
        return animate(
            "opacity",
            _decimalToString(fromOpacity, 3),
            _decimalToString(toOpacity, 3),
            config
        );
    }

    /**
     * @notice Create path morphing animation
     * @param fromPath Start path d attribute
     * @param toPath End path d attribute
     * @param config Animation configuration
     * @return SVG animate for path morphing
     */
    function animatePath(
        string memory fromPath,
        string memory toPath,
        AnimationConfig memory config
    ) internal pure returns (string memory) {
        return animate("d", fromPath, toPath, config);
    }

    /**
     * @notice Create stroke dash animation (drawing effect)
     * @param pathLength Total path length
     * @param config Animation configuration
     * @return SVG style and animate elements for draw effect
     */
    function animateStrokeDraw(
        uint256 pathLength,
        AnimationConfig memory config
    ) internal pure returns (string memory) {
        string memory length = _uintToString(pathLength);

        return string(
            abi.encodePacked(
                'stroke-dasharray="', length, '" stroke-dashoffset="', length, '"',
                '<animate attributeName="stroke-dashoffset" ',
                'from="', length, '" to="0" ',
                _buildAnimationAttrs(config),
                '/>'
            )
        );
    }

    // ============ ANIMATION PRESETS ============

    /**
     * @notice Create pulse animation preset
     * @param intensity Pulse intensity (scale factor, 1000-2000)
     * @return Animation config for pulse
     */
    function pulsePreset(uint256 intensity) internal pure returns (AnimationConfig memory) {
        return AnimationConfig({
            duration: 1000,
            delay: 0,
            iterations: 0, // infinite
            alternate: true,
            fillMode: FillMode.None
        });
    }

    /**
     * @notice Create fade-in animation preset
     * @param duration Duration in ms
     * @return Animation config for fade-in
     */
    function fadeInPreset(uint256 duration) internal pure returns (AnimationConfig memory) {
        return AnimationConfig({
            duration: duration,
            delay: 0,
            iterations: 1,
            alternate: false,
            fillMode: FillMode.Forwards
        });
    }

    /**
     * @notice Create spin animation preset
     * @param duration Duration per rotation in ms
     * @return Animation config for continuous spin
     */
    function spinPreset(uint256 duration) internal pure returns (AnimationConfig memory) {
        return AnimationConfig({
            duration: duration,
            delay: 0,
            iterations: 0, // infinite
            alternate: false,
            fillMode: FillMode.None
        });
    }

    /**
     * @notice Create bounce animation preset
     * @return Animation config for bounce
     */
    function bouncePreset() internal pure returns (AnimationConfig memory) {
        return AnimationConfig({
            duration: 600,
            delay: 0,
            iterations: 0,
            alternate: true,
            fillMode: FillMode.None
        });
    }

    // ============ KEYFRAME HELPERS ============

    /**
     * @notice Generate values string from keyframe array
     * @param keyframes Array of keyframes
     * @return Semicolon-separated values string
     */
    function buildKeyframeValues(Keyframe[] memory keyframes) internal pure returns (string memory) {
        if (keyframes.length == 0) return "";

        string memory result = _intToString(keyframes[0].value);

        for (uint256 i = 1; i < keyframes.length; i++) {
            result = string(abi.encodePacked(result, ";", _intToString(keyframes[i].value)));
        }

        return result;
    }

    /**
     * @notice Generate keyTimes string from keyframe array
     * @param keyframes Array of keyframes
     * @return Semicolon-separated keyTimes string
     */
    function buildKeyframeTimes(Keyframe[] memory keyframes) internal pure returns (string memory) {
        if (keyframes.length == 0) return "";

        string memory result = _decimalToString(keyframes[0].time, 3);

        for (uint256 i = 1; i < keyframes.length; i++) {
            result = string(abi.encodePacked(result, ";", _decimalToString(keyframes[i].time, 3)));
        }

        return result;
    }

    /**
     * @notice Interpolate value between keyframes
     * @param keyframes Array of keyframes
     * @param time Current time (0-1000)
     * @return Interpolated value
     */
    function interpolateKeyframes(Keyframe[] memory keyframes, uint256 time) internal pure returns (int256) {
        if (keyframes.length == 0) return 0;
        if (keyframes.length == 1) return keyframes[0].value;

        // Find surrounding keyframes
        uint256 nextIdx = 0;
        for (uint256 i = 0; i < keyframes.length; i++) {
            if (keyframes[i].time > time) {
                nextIdx = i;
                break;
            }
            if (i == keyframes.length - 1) {
                return keyframes[i].value;
            }
        }

        if (nextIdx == 0) return keyframes[0].value;

        Keyframe memory prev = keyframes[nextIdx - 1];
        Keyframe memory next = keyframes[nextIdx];

        // Calculate local progress
        uint256 localProgress;
        if (next.time > prev.time) {
            localProgress = ((time - prev.time) * PRECISION) / (next.time - prev.time);
        }

        // Apply easing
        uint256 easedProgress = ease(localProgress, prev.easing);

        // Interpolate
        if (next.value >= prev.value) {
            return prev.value + int256((uint256(next.value - prev.value) * easedProgress) / PRECISION);
        } else {
            return prev.value - int256((uint256(prev.value - next.value) * easedProgress) / PRECISION);
        }
    }

    // ============ CSS ANIMATION GENERATION ============

    /**
     * @notice Generate CSS keyframes rule
     * @param name Animation name
     * @param keyframes CSS keyframe definitions
     * @return CSS @keyframes rule
     */
    function cssKeyframes(string memory name, string memory keyframes) internal pure returns (string memory) {
        return string(abi.encodePacked("@keyframes ", name, " { ", keyframes, " }"));
    }

    /**
     * @notice Generate CSS animation property
     * @param name Animation name
     * @param config Animation configuration
     * @return CSS animation property value
     */
    function cssAnimation(string memory name, AnimationConfig memory config) internal pure returns (string memory) {
        string memory iterCount = config.iterations == 0 ? "infinite" : _uintToString(config.iterations);
        string memory direction = config.alternate ? "alternate" : "normal";
        string memory fill = _fillModeToString(config.fillMode);

        return string(
            abi.encodePacked(
                name, " ",
                _uintToString(config.duration), "ms ",
                _uintToString(config.delay), "ms ",
                iterCount, " ",
                direction, " ",
                fill
            )
        );
    }

    // ============ INTERNAL HELPERS ============

    /**
     * @notice Build common animation attributes string
     */
    function _buildAnimationAttrs(AnimationConfig memory config) internal pure returns (string memory) {
        string memory dur = string(abi.encodePacked(_uintToString(config.duration), "ms"));
        string memory iterCount = config.iterations == 0 ? "indefinite" : _uintToString(config.iterations);
        string memory fill = _fillModeToString(config.fillMode);

        string memory attrs = string(
            abi.encodePacked(
                'dur="', dur, '" ',
                'repeatCount="', iterCount, '" ',
                'fill="', fill, '"'
            )
        );

        if (config.delay > 0) {
            attrs = string(abi.encodePacked(attrs, ' begin="', _uintToString(config.delay), 'ms"'));
        }

        return attrs;
    }

    /**
     * @notice Convert fill mode to string
     */
    function _fillModeToString(FillMode mode) internal pure returns (string memory) {
        if (mode == FillMode.Forwards) return "freeze";
        if (mode == FillMode.Backwards) return "freeze";
        if (mode == FillMode.Both) return "freeze";
        return "remove";
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

    /**
     * @notice Convert uint256 to string
     */
    function _uintToString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";

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
     * @notice Convert int256 to string
     */
    function _intToString(int256 value) internal pure returns (string memory) {
        if (value >= 0) {
            return _uintToString(uint256(value));
        }
        return string(abi.encodePacked("-", _uintToString(uint256(-value))));
    }

    /**
     * @notice Convert decimal value to string (value / 10^decimals)
     */
    function _decimalToString(uint256 value, uint256 decimals) internal pure returns (string memory) {
        uint256 divisor = 10 ** decimals;
        uint256 wholePart = value / divisor;
        uint256 fracPart = value % divisor;

        if (fracPart == 0) {
            return _uintToString(wholePart);
        }

        while (fracPart > 0 && fracPart % 10 == 0) {
            fracPart /= 10;
        }

        return string(abi.encodePacked(_uintToString(wholePart), ".", _uintToString(fracPart)));
    }
}
