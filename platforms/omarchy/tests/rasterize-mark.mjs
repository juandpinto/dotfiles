// Rasterises the bar module's monogram paths into the About/fastfetch block
// text, so the two stay one drawing. Usage: node rasterize-mark.mjs <jdp-menu.qml>
// Reads the two PathSvg strings (M/H/V/L/Z only), fills them even-odd on a
// pixel grid (1 column = 1 half-row) at <scale> pixels per path unit, shears
// each half-row for the 12-degree lean, and packs half-block characters.
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export function rasterizeMark(qml, scale = 0.75) {
    const paths = [...qml.matchAll(/PathSvg \{ path: "([^"]+)" \}/g)].map(match => match[1]);
    if (paths.length !== 2) throw new Error(`expected 2 PathSvg, found ${paths.length}`);
    const polygons = paths.flatMap(parsePath);
    const R = value => Math.round(value * scale);
    const minY = R(4), maxY = R(76), width = R(92);
    const lean = Math.tan(12 * Math.PI / 180);
    const grid = [];
    for (let y = minY; y < maxY; y++) {
        const row = new Array(width).fill(false);
        const shift = Math.round((maxY - y) * lean);
        for (let x = 0; x < width; x++) {
            const px = (x - shift + 0.5) / scale, py = (y + 0.5) / scale;
            row[x] = polygons.reduce((inside, polygon) => inside !== contains(polygon, px, py), false);
        }
        grid.push(row);
    }
    const top = minY % 2 ? minY - 1 : minY;
    if (top < minY) grid.unshift(new Array(width).fill(false));
    const lines = [];
    for (let y = 0; y < grid.length; y += 2) {
        const a = grid[y], b = grid[y + 1] ?? new Array(width).fill(false);
        lines.push([...a].map((on, x) => (on && b[x] ? '█' : on ? '▀' : b[x] ? '▄' : ' ')).join('').trimEnd());
    }
    while (lines.length && !lines[0]) lines.shift();
    const indent = Math.min(...lines.filter(line => line).map(line => line.match(/^ */)[0].length));
    return lines.map(line => line.slice(indent)).join('\n').trimEnd();
}

function parsePath(path) {
    const polygons = [];
    let current = [], x = 0, y = 0;
    for (const [, command, args] of path.matchAll(/([MHVLZ])\s*([-\d.\s]*)/g)) {
        const nums = args.trim().split(/\s+/).filter(Boolean).map(Number);
        if (command === 'M') { if (current.length) polygons.push(current); current = []; [x, y] = nums; }
        else if (command === 'H') x = nums[0];
        else if (command === 'V') y = nums[0];
        else if (command === 'L') [x, y] = nums;
        else if (command === 'Z') { if (current.length) polygons.push(current); current = []; continue; }
        current.push([x, y]);
    }
    if (current.length) polygons.push(current);
    return polygons;
}

function contains(polygon, px, py) {
    let inside = false;
    for (let i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
        const [xi, yi] = polygon[i], [xj, yj] = polygon[j];
        if ((yi > py) !== (yj > py) && px < ((xj - xi) * (py - yi)) / (yj - yi) + xi) inside = !inside;
    }
    return inside;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === resolve(process.argv[1])) {
    console.log(rasterizeMark(readFileSync(process.argv[2], 'utf8'), Number(process.argv[3] ?? 0.75)));
}
