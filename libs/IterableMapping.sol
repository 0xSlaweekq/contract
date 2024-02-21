// SPDX-License-Identifier: NONE
pragma solidity ^0.8.0;

library IterableMapping {
    // Iterable mapping from address to uint;
    struct Map {
        address[] keys;
        mapping(address => uint256) values;
        mapping(address => uint256) indexOf;
        mapping(address => bool) inserted;
    }

    function _remove(Map storage map, address key) internal {
        if (!map.inserted[key]) return;

        delete map.inserted[key];
        delete map.values[key];

        uint256 index = map.indexOf[key];
        uint256 lastIndex = map.keys.length - 1;
        address lastKey = map.keys[lastIndex];

        map.indexOf[lastKey] = index;
        delete map.indexOf[key];

        map.keys[index] = lastKey;
        map.keys.pop();
    }

    function _set(Map storage map, address key, uint256 val) internal {
        if (map.inserted[key]) {
            map.values[key] = val;
        } else {
            map.inserted[key] = true;
            map.values[key] = val;
            map.indexOf[key] = map.keys.length;
            map.keys.push(key);
        }
    }

    function _get(Map storage map, address key) internal view returns (uint256 values) {
        return map.values[key];
    }

    function _getIndexOfKey(Map storage map, address key) internal view returns (int256 indexOf) {
        if (!map.inserted[key]) return -1;

        return int256(map.indexOf[key]);
    }

    function _getKeyAtIndex(Map storage map, uint256 index) internal view returns (address keys) {
        return map.keys[index];
    }

    function _size(Map storage map) internal view returns (uint256 length) {
        return map.keys.length;
    }
}
