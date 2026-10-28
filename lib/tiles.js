.pragma library

// Rule 4: a tile group fills whole rows.
function fullRows(count, columns) {
    return columns > 0 && count > 0 && count % columns === 0;
}
