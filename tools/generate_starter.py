"""Build a deterministic offline starter pool of deduction-certified 6/9/12 puzzles.

Uses no giant permutation lists. A clue is an actual planted cat, never a guessed
answer; uniqueness and deductibility are checked under the same public clue.
"""
from __future__ import annotations
import collections
import json
import random
from pathlib import Path

SEED = 628145
TARGET = 8
SIZE = {"easy": 6, "medium": 9, "hard": 12}
CAPS = {"easy": 2, "medium": 6, "hard": 9}


def shuffle_queens(n: int, rng: random.Random) -> list[int]:
    result: list[int] = []

    def place(used: int) -> bool:
        if len(result) == n:
            return True
        options = list(range(n))
        rng.shuffle(options)
        for col in options:
            if used & (1 << col) or (result and abs(col - result[-1]) <= 1):
                continue
            result.append(col)
            if place(used | (1 << col)):
                return True
            result.pop()
        return False

    if not place(0):
        raise RuntimeError(f"Could not find {n}-cat pattern")
    return result


def grow_regions(n: int, queens: list[int], caps: dict[int, int], rng: random.Random) -> list[int] | None:
    board = [-1] * (n * n)
    sizes = [1] * n
    front: list[tuple[int, int]] = []

    def neighbors(index: int):
        y, x = divmod(index, n)
        for yy, xx in ((y-1, x), (y+1, x), (y, x-1), (y, x+1)):
            if 0 <= yy < n and 0 <= xx < n:
                yield yy * n + xx

    for y, col in enumerate(queens):
        board[y*n+col] = y
    for y, col in enumerate(queens):
        for other in neighbors(y*n+col):
            if board[other] < 0:
                front.append((other, y))
    remaining = n*n-n
    while remaining:
        if not front:
            return None
        j = rng.randrange(len(front))
        target, region = front[j]
        front[j] = front[-1]
        front.pop()
        if board[target] >= 0 or sizes[region] >= caps.get(region, n*n):
            continue
        board[target] = region
        sizes[region] += 1
        remaining -= 1
        for other in neighbors(target):
            if board[other] < 0:
                front.append((other, region))
    return board


def count_solutions(n: int, regions: list[int], givens: list[int] | None = None, limit: int = 2) -> tuple[int, tuple[int, ...]]:
    pinned = {i // n: i % n for i in (givens or [])}
    result = 0
    first_solution: tuple[int, ...] = ()
    path: list[int] = []

    def search(row: int, cols: int, areas: int, prev: int) -> None:
        nonlocal result, first_solution
        if result >= limit:
            return
        if row == n:
            result += 1
            if result == 1:
                first_solution = tuple(path)
            return
        candidates = (pinned[row],) if row in pinned else range(n)
        for col in candidates:
            color = regions[row*n+col]
            if cols & (1 << col) or areas & (1 << color) or (row and abs(col-prev) <= 1):
                continue
            path.append(col)
            search(row+1, cols | (1 << col), areas | (1 << color), col)
            path.pop()
            if result >= limit:
                return

    search(0, 0, 0, -5)
    return result, first_solution


def deduction(n: int, regions: list[int], givens: list[int] | None = None) -> tuple[bool, int, int, tuple[int, ...]]:
    candidate = [True] * (n*n)
    fixed = set(givens or [])
    support = 0
    for passes in range(1, 101):
        changed = False
        for pos in tuple(fixed):
            y, x = divmod(pos, n)
            for j in range(n*n):
                yy, xx = divmod(j, n)
                if j != pos and candidate[j] and (y == yy or x == xx or regions[j] == regions[pos] or (abs(y-yy) <= 1 and abs(x-xx) <= 1)):
                    candidate[j] = False
                    changed = True
        groups = ([range(y*n, (y+1)*n) for y in range(n)]
                  + [[y*n+x for y in range(n)] for x in range(n)]
                  + [[j for j, c in enumerate(regions) if c == reg] for reg in range(n)])
        for group in groups:
            available = [j for j in group if candidate[j]]
            if not available:
                return False, passes, support, tuple(fixed)
            if len(available) == 1 and available[0] not in fixed:
                fixed.add(available[0])
                changed = True
        for pos in range(n*n):
            if not candidate[pos]:
                continue
            y, x = divmod(pos, n)
            for yy in (y-1, y+1):
                if 0 <= yy < n and not any(candidate[yy*n+xx] and abs(xx-x) > 1 for xx in range(n)):
                    candidate[pos] = False
                    support += 1
                    changed = True
                    break
        if len(fixed) == n:
            return all(candidate[pos] for pos in fixed), passes, support, tuple(sorted(fixed))
        if not changed:
            break
    return False, passes, support, tuple(sorted(fixed))


def connected(n: int, regions: list[int]) -> bool:
    if len(regions) != n*n or set(regions) != set(range(n)):
        return False
    for region in range(n):
        start = regions.index(region)
        visited = {start}
        stack = [start]
        while stack:
            y, x = divmod(stack.pop(), n)
            for yy, xx in ((y-1, x), (y+1, x), (y, x-1), (y, x+1)):
                j = yy*n+xx
                if 0 <= yy < n and 0 <= xx < n and regions[j] == region and j not in visited:
                    visited.add(j)
                    stack.append(j)
        if len(visited) != regions.count(region):
            return False
    return True


def make_puzzle(level: str, rng: random.Random, with_cat: bool, max_attempts: int = 200000) -> tuple[dict, tuple[int, int]]:
    n = SIZE[level]
    small_count = CAPS[level]
    for tries in range(1, max_attempts + 1):
        queens = shuffle_queens(n, rng)
        small_ids = rng.sample(range(n), small_count)
        caps = {key: rng.choice((1, 2, 2)) for key in small_ids}
        board = grow_regions(n, queens, caps, rng)
        if board is None:
            continue
        # Avoid a single colour covering more than half the visible board.
        if max(collections.Counter(board).values()) > n*n//2:
            continue
        givens = []
        if with_cat:
            row = rng.randrange(n)
            givens = [row*n + queens[row]]
        num, solution = count_solutions(n, board, givens)
        if num != 1:
            continue
        okay, passes, support, fixed = deduction(n, board, givens)
        if not okay:
            continue
        # Preserve a deduction progression on 9/12, despite obvious islands.
        if level == "medium" and passes < 4 or level == "hard" and passes < (5 if with_cat else 6):
            continue
        assert solution == tuple(next(i % n for i in fixed if i//n == y) for y in range(n))
        assert connected(n, board)
        return {"size": n, "regions": board, "givens": givens}, (tries, passes)
    raise RuntimeError(f"Exhausted {max_attempts} attempts for {level} (clue={with_cat})")


def main() -> None:
    rng = random.Random(SEED)
    entries = {}
    for level in SIZE:
        values = []
        seen = set()
        for index in range(TARGET):
            with_cat = index in (2, 6)  # 2/8 starters per difficulty begin with one immutable cat.
            while True:
                puzzle, diagnostics = make_puzzle(level, rng, with_cat)
                signature = tuple(puzzle["regions"])
                if signature not in seen:
                    break
            seen.add(signature)
            values.append(puzzle)
            print(level, index + 1, "clue", with_cat, "attempts", diagnostics[0], "deduction passes", diagnostics[1], flush=True)
        entries[level] = values
    root = Path(__file__).resolve().parent.parent
    target = root / "data" / "starter_puzzles.json"
    target.write_text(json.dumps({"version": 2, "puzzles": entries}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    assert len(entries) == 3 and all(len(group) == 8 for group in entries.values())
    print("Certified", sum(len(group) for group in entries.values()), "starter boards:", target, target.stat().st_size, "bytes", flush=True)


if __name__ == "__main__":
    main()
