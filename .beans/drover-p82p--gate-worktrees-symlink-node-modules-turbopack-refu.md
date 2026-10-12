---
# drover-p82p
title: Gate worktrees symlink node_modules; Turbopack refuses a symlink outside the project root
status: completed
type: bug
priority: normal
created_at: 2026-10-12T09:53:12Z
updated_at: 2026-10-12T19:41:45Z
---

fleet-verify-main (bin/fleet-verify-main:43-45) and fleet-land-bean (bin/fleet-land-bean:105-107) seed DROVER_CLONE_DIRS into the gate worktree with `ln -s "$REPO/$d" "$wt/$d"`. Seat worktrees use drover_clone (bin/fleet:475), a copy-on-write copy.

Next.js 16 `next build` (Turbopack) fails on the symlink:

    Error [TurbopackInternalError]: Symlink [project]/node_modules is invalid, it points out of the filesystem root

Seen 2026-10-12 on the panel2 project: the cumulative gate went RED on a green main, and fleet-push refused to push. Workaround in that project's config: DROVER_TEST_ALL runs `rm -rf node_modules && npm ci` first.

Fix: seed the gate worktrees with drover_clone, the same as seats. Keep the symlink only as a fallback when drover_clone fails (no copy-on-write and a huge tree).

- [x] fleet-verify-main and fleet-land-bean use drover_clone for DROVER_CLONE_DIRS
- [x] a project with Turbopack passes the push gate without an npm ci in DROVER_TEST_ALL
- [x] README gate section says the gate worktree holds a copy, not a symlink

2026-10-12 16:15, panel2: the cumulative verify runs DROVER_BUILD (tsc) in the verify worktree before DROVER_TEST_ALL runs npm ci. The worktree shares the main checkout node_modules, so a bean that adds a package (panel2-33bs, basic-ftp) fails the push gate with TS2307 until someone runs npm ci in the main checkout. Fix idea: run the install step before the build, or install when package-lock.json differs from the checkout.
