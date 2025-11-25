// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title DateTimeLib
 * @notice Gas-efficient date and time manipulation library
 * @dev Provides utilities for:
 *      - Timestamp to date/time component conversion
 *      - Date arithmetic (add/subtract days, months, years)
 *      - Weekday calculation
 *      - Time period validation (business hours, weekends, etc.)
 *
 *      Uses Unix timestamps (seconds since 1970-01-01 00:00:00 UTC)
 */
library DateTimeLib {
    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    uint256 internal constant SECONDS_PER_MINUTE = 60;
    uint256 internal constant SECONDS_PER_HOUR = 3600;
    uint256 internal constant SECONDS_PER_DAY = 86400;
    uint256 internal constant SECONDS_PER_WEEK = 604800;
    uint256 internal constant SECONDS_PER_YEAR = 31536000;      // Non-leap year
    uint256 internal constant SECONDS_PER_LEAP_YEAR = 31622400;

    uint256 internal constant DAYS_PER_WEEK = 7;
    uint256 internal constant DAYS_PER_YEAR = 365;
    uint256 internal constant DAYS_PER_LEAP_YEAR = 366;

    // Days from start of year to start of each month (non-leap)
    uint16[12] internal constant DAYS_BEFORE_MONTH = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334];

    // Days in each month (non-leap)
    uint8[12] internal constant DAYS_IN_MONTH = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];

    // Weekday constants (1 = Monday, 7 = Sunday)
    uint256 internal constant MONDAY = 1;
    uint256 internal constant TUESDAY = 2;
    uint256 internal constant WEDNESDAY = 3;
    uint256 internal constant THURSDAY = 4;
    uint256 internal constant FRIDAY = 5;
    uint256 internal constant SATURDAY = 6;
    uint256 internal constant SUNDAY = 7;

    // ═══════════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @dev Date components struct
     */
    struct DateTime {
        uint16 year;
        uint8 month;    // 1-12
        uint8 day;      // 1-31
        uint8 hour;     // 0-23
        uint8 minute;   // 0-59
        uint8 second;   // 0-59
        uint8 weekday;  // 1-7 (Mon-Sun)
    }

    /**
     * @dev Date only (no time component)
     */
    struct Date {
        uint16 year;
        uint8 month;
        uint8 day;
    }

    /**
     * @dev Time only (no date component)
     */
    struct Time {
        uint8 hour;
        uint8 minute;
        uint8 second;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error InvalidDate();
    error InvalidTime();
    error TimestampOverflow();
    error DateBeforeEpoch();

    // ═══════════════════════════════════════════════════════════════════════════
    // TIMESTAMP TO COMPONENTS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Converts a Unix timestamp to DateTime components
     * @param timestamp Unix timestamp (seconds since epoch)
     * @return dt The DateTime struct
     */
    function toDateTime(uint256 timestamp) internal pure returns (DateTime memory dt) {
        (dt.year, dt.month, dt.day) = toDate(timestamp);
        (dt.hour, dt.minute, dt.second) = toTime(timestamp);
        dt.weekday = getWeekday(timestamp);
    }

    /**
     * @notice Extracts the year from a timestamp
     * @param timestamp Unix timestamp
     * @return year The year
     */
    function getYear(uint256 timestamp) internal pure returns (uint16 year) {
        (year, , ) = toDate(timestamp);
    }

    /**
     * @notice Extracts the month from a timestamp
     * @param timestamp Unix timestamp
     * @return month The month (1-12)
     */
    function getMonth(uint256 timestamp) internal pure returns (uint8 month) {
        (, month, ) = toDate(timestamp);
    }

    /**
     * @notice Extracts the day from a timestamp
     * @param timestamp Unix timestamp
     * @return day The day (1-31)
     */
    function getDay(uint256 timestamp) internal pure returns (uint8 day) {
        (, , day) = toDate(timestamp);
    }

    /**
     * @notice Extracts the hour from a timestamp
     * @param timestamp Unix timestamp
     * @return hour The hour (0-23)
     */
    function getHour(uint256 timestamp) internal pure returns (uint8 hour) {
        hour = uint8((timestamp / SECONDS_PER_HOUR) % 24);
    }

    /**
     * @notice Extracts the minute from a timestamp
     * @param timestamp Unix timestamp
     * @return minute The minute (0-59)
     */
    function getMinute(uint256 timestamp) internal pure returns (uint8 minute) {
        minute = uint8((timestamp / SECONDS_PER_MINUTE) % 60);
    }

    /**
     * @notice Extracts the second from a timestamp
     * @param timestamp Unix timestamp
     * @return second The second (0-59)
     */
    function getSecond(uint256 timestamp) internal pure returns (uint8 second) {
        second = uint8(timestamp % 60);
    }

    /**
     * @notice Converts timestamp to date components (year, month, day)
     * @param timestamp Unix timestamp
     * @return year The year
     * @return month The month (1-12)
     * @return day The day (1-31)
     */
    function toDate(
        uint256 timestamp
    ) internal pure returns (uint16 year, uint8 month, uint8 day) {
        unchecked {
            // Days since epoch
            uint256 totalDays = timestamp / SECONDS_PER_DAY;

            // Calculate year using approximation then adjustment
            year = 1970;

            // Fast forward by 400-year cycles
            uint256 cycles400 = totalDays / 146097;
            year += uint16(cycles400 * 400);
            totalDays -= cycles400 * 146097;

            // Then by 100-year cycles
            uint256 cycles100 = totalDays / 36524;
            if (cycles100 == 4) cycles100 = 3; // Edge case
            year += uint16(cycles100 * 100);
            totalDays -= cycles100 * 36524;

            // Then by 4-year cycles
            uint256 cycles4 = totalDays / 1461;
            year += uint16(cycles4 * 4);
            totalDays -= cycles4 * 1461;

            // Then by individual years
            uint256 remainingYears = totalDays / 365;
            if (remainingYears == 4) remainingYears = 3; // Edge case
            year += uint16(remainingYears);
            totalDays -= remainingYears * 365;

            // Now totalDays is day of year (0-indexed)
            bool isLeap = isLeapYear(year);

            // Find month
            month = 1;
            uint256 daysInCurrentMonth;
            while (month <= 12) {
                if (month == 2 && isLeap) {
                    daysInCurrentMonth = 29;
                } else {
                    daysInCurrentMonth = DAYS_IN_MONTH[month - 1];
                }

                if (totalDays < daysInCurrentMonth) {
                    break;
                }
                totalDays -= daysInCurrentMonth;
                month++;
            }

            day = uint8(totalDays + 1);
        }
    }

    /**
     * @notice Extracts time components from timestamp
     * @param timestamp Unix timestamp
     * @return hour The hour (0-23)
     * @return minute The minute (0-59)
     * @return second The second (0-59)
     */
    function toTime(
        uint256 timestamp
    ) internal pure returns (uint8 hour, uint8 minute, uint8 second) {
        unchecked {
            uint256 secondsOfDay = timestamp % SECONDS_PER_DAY;
            hour = uint8(secondsOfDay / SECONDS_PER_HOUR);
            minute = uint8((secondsOfDay % SECONDS_PER_HOUR) / SECONDS_PER_MINUTE);
            second = uint8(secondsOfDay % SECONDS_PER_MINUTE);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // COMPONENTS TO TIMESTAMP
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Converts date/time components to Unix timestamp
     * @param year The year (>= 1970)
     * @param month The month (1-12)
     * @param day The day (1-31)
     * @param hour The hour (0-23)
     * @param minute The minute (0-59)
     * @param second The second (0-59)
     * @return timestamp Unix timestamp
     */
    function toTimestamp(
        uint16 year,
        uint8 month,
        uint8 day,
        uint8 hour,
        uint8 minute,
        uint8 second
    ) internal pure returns (uint256 timestamp) {
        if (year < 1970) revert DateBeforeEpoch();
        if (month < 1 || month > 12) revert InvalidDate();
        if (day < 1 || day > getDaysInMonth(year, month)) revert InvalidDate();
        if (hour > 23 || minute > 59 || second > 59) revert InvalidTime();

        unchecked {
            // Days from years
            uint256 totalDays = 0;
            for (uint16 y = 1970; y < year; y++) {
                totalDays += isLeapYear(y) ? DAYS_PER_LEAP_YEAR : DAYS_PER_YEAR;
            }

            // Days from months
            for (uint8 m = 1; m < month; m++) {
                totalDays += getDaysInMonth(year, m);
            }

            // Days from day of month
            totalDays += day - 1;

            // Convert to seconds and add time
            timestamp = totalDays * SECONDS_PER_DAY +
                        uint256(hour) * SECONDS_PER_HOUR +
                        uint256(minute) * SECONDS_PER_MINUTE +
                        uint256(second);
        }
    }

    /**
     * @notice Converts date components to Unix timestamp (midnight UTC)
     * @param year The year (>= 1970)
     * @param month The month (1-12)
     * @param day The day (1-31)
     * @return timestamp Unix timestamp
     */
    function toTimestamp(
        uint16 year,
        uint8 month,
        uint8 day
    ) internal pure returns (uint256 timestamp) {
        return toTimestamp(year, month, day, 0, 0, 0);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // DATE ARITHMETIC
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Adds days to a timestamp
     * @param timestamp Starting timestamp
     * @param numDays Number of days to add
     * @return newTimestamp Resulting timestamp
     */
    function addDays(uint256 timestamp, uint256 numDays) internal pure returns (uint256 newTimestamp) {
        newTimestamp = timestamp + (numDays * SECONDS_PER_DAY);
    }

    /**
     * @notice Subtracts days from a timestamp
     * @param timestamp Starting timestamp
     * @param numDays Number of days to subtract
     * @return newTimestamp Resulting timestamp
     */
    function subDays(uint256 timestamp, uint256 numDays) internal pure returns (uint256 newTimestamp) {
        uint256 toSubtract = numDays * SECONDS_PER_DAY;
        if (toSubtract > timestamp) revert DateBeforeEpoch();
        newTimestamp = timestamp - toSubtract;
    }

    /**
     * @notice Adds months to a timestamp
     * @param timestamp Starting timestamp
     * @param numMonths Number of months to add
     * @return newTimestamp Resulting timestamp
     */
    function addMonths(uint256 timestamp, uint256 numMonths) internal pure returns (uint256 newTimestamp) {
        (uint16 year, uint8 month, uint8 day) = toDate(timestamp);
        (uint8 hour, uint8 minute, uint8 second) = toTime(timestamp);

        uint256 totalMonths = uint256(month) - 1 + numMonths;
        year += uint16(totalMonths / 12);
        month = uint8((totalMonths % 12) + 1);

        // Clamp day if needed
        uint8 maxDay = getDaysInMonth(year, month);
        if (day > maxDay) day = maxDay;

        newTimestamp = toTimestamp(year, month, day, hour, minute, second);
    }

    /**
     * @notice Adds years to a timestamp
     * @param timestamp Starting timestamp
     * @param numYears Number of years to add
     * @return newTimestamp Resulting timestamp
     */
    function addYears(uint256 timestamp, uint256 numYears) internal pure returns (uint256 newTimestamp) {
        (uint16 year, uint8 month, uint8 day) = toDate(timestamp);
        (uint8 hour, uint8 minute, uint8 second) = toTime(timestamp);

        year += uint16(numYears);

        // Handle Feb 29 -> Feb 28 for non-leap years
        if (month == 2 && day == 29 && !isLeapYear(year)) {
            day = 28;
        }

        newTimestamp = toTimestamp(year, month, day, hour, minute, second);
    }

    /**
     * @notice Calculates the difference in days between two timestamps
     * @param timestampFrom Starting timestamp
     * @param timestampTo Ending timestamp
     * @return daysDiff The difference in days (can be negative)
     */
    function diffDays(uint256 timestampFrom, uint256 timestampTo) internal pure returns (int256 daysDiff) {
        if (timestampTo >= timestampFrom) {
            daysDiff = int256((timestampTo - timestampFrom) / SECONDS_PER_DAY);
        } else {
            daysDiff = -int256((timestampFrom - timestampTo) / SECONDS_PER_DAY);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // WEEKDAY & CALENDAR
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Gets the day of the week for a timestamp
     * @param timestamp Unix timestamp
     * @return weekday Day of week (1=Monday, 7=Sunday)
     */
    function getWeekday(uint256 timestamp) internal pure returns (uint8 weekday) {
        // January 1, 1970 was a Thursday (4)
        unchecked {
            uint256 daysSinceEpoch = timestamp / SECONDS_PER_DAY;
            weekday = uint8(((daysSinceEpoch + 3) % 7) + 1);
        }
    }

    /**
     * @notice Checks if a timestamp falls on a weekend
     * @param timestamp Unix timestamp
     * @return isWeekend True if Saturday or Sunday
     */
    function isWeekend(uint256 timestamp) internal pure returns (bool) {
        uint8 weekday = getWeekday(timestamp);
        return weekday == SATURDAY || weekday == SUNDAY;
    }

    /**
     * @notice Checks if a timestamp falls on a weekday (Mon-Fri)
     * @param timestamp Unix timestamp
     * @return isWeekday True if Monday through Friday
     */
    function isWeekday(uint256 timestamp) internal pure returns (bool) {
        return !isWeekend(timestamp);
    }

    /**
     * @notice Gets the timestamp of the start of the day (midnight UTC)
     * @param timestamp Any timestamp within the day
     * @return startOfDay Timestamp at 00:00:00 UTC
     */
    function startOfDay(uint256 timestamp) internal pure returns (uint256) {
        return (timestamp / SECONDS_PER_DAY) * SECONDS_PER_DAY;
    }

    /**
     * @notice Gets the timestamp of the end of the day (23:59:59 UTC)
     * @param timestamp Any timestamp within the day
     * @return endOfDay Timestamp at 23:59:59 UTC
     */
    function endOfDay(uint256 timestamp) internal pure returns (uint256) {
        return startOfDay(timestamp) + SECONDS_PER_DAY - 1;
    }

    /**
     * @notice Gets the timestamp of the start of the month
     * @param timestamp Any timestamp within the month
     * @return startOfMonth Timestamp at start of month
     */
    function startOfMonth(uint256 timestamp) internal pure returns (uint256) {
        (uint16 year, uint8 month, ) = toDate(timestamp);
        return toTimestamp(year, month, 1);
    }

    /**
     * @notice Gets the timestamp of the start of the year
     * @param timestamp Any timestamp within the year
     * @return startOfYear Timestamp at January 1, 00:00:00
     */
    function startOfYear(uint256 timestamp) internal pure returns (uint256) {
        uint16 year = getYear(timestamp);
        return toTimestamp(year, 1, 1);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Checks if a year is a leap year
     * @param year The year to check
     * @return isLeap True if leap year
     */
    function isLeapYear(uint16 year) internal pure returns (bool isLeap) {
        isLeap = (year % 4 == 0) && (year % 100 != 0 || year % 400 == 0);
    }

    /**
     * @notice Gets the number of days in a month
     * @param year The year
     * @param month The month (1-12)
     * @return days Number of days in the month
     */
    function getDaysInMonth(uint16 year, uint8 month) internal pure returns (uint8 days) {
        if (month < 1 || month > 12) revert InvalidDate();

        if (month == 2 && isLeapYear(year)) {
            return 29;
        }
        return DAYS_IN_MONTH[month - 1];
    }

    /**
     * @notice Gets the day of the year (1-366)
     * @param timestamp Unix timestamp
     * @return dayOfYear The day number within the year
     */
    function getDayOfYear(uint256 timestamp) internal pure returns (uint16 dayOfYear) {
        (uint16 year, uint8 month, uint8 day) = toDate(timestamp);

        dayOfYear = day;
        for (uint8 m = 1; m < month; m++) {
            dayOfYear += getDaysInMonth(year, m);
        }
    }

    /**
     * @notice Gets the week number of the year (ISO 8601)
     * @param timestamp Unix timestamp
     * @return weekNumber The week number (1-53)
     */
    function getWeekOfYear(uint256 timestamp) internal pure returns (uint8 weekNumber) {
        uint16 dayOfYear = getDayOfYear(timestamp);
        uint8 weekday = getWeekday(timestamp);

        // ISO 8601: Week 1 contains the first Thursday of the year
        int256 weekNum = (int256(uint256(dayOfYear)) - int256(uint256(weekday)) + 10) / 7;

        if (weekNum < 1) {
            // Last week of previous year
            weekNumber = 52;
        } else if (weekNum > 52) {
            // Check if it's week 53 or week 1 of next year
            weekNumber = 1;
        } else {
            weekNumber = uint8(uint256(weekNum));
        }
    }

    /**
     * @notice Validates a date
     * @param year The year
     * @param month The month
     * @param day The day
     * @return valid True if the date is valid
     */
    function isValidDate(uint16 year, uint8 month, uint8 day) internal pure returns (bool valid) {
        if (year < 1970) return false;
        if (month < 1 || month > 12) return false;
        if (day < 1 || day > getDaysInMonth(year, month)) return false;
        return true;
    }

    /**
     * @notice Validates a time
     * @param hour The hour
     * @param minute The minute
     * @param second The second
     * @return valid True if the time is valid
     */
    function isValidTime(uint8 hour, uint8 minute, uint8 second) internal pure returns (bool valid) {
        return hour <= 23 && minute <= 59 && second <= 59;
    }
}
