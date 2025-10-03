# 📦 How Console Changes Flow into Docker Image

## Overview

The lakekeeper-console repository (Vue.js UI) is **embedded at compile-time** into the Rust binary through a clever build process. Here's the complete flow:

## 🔄 The Flow Diagram

```
lakekeeper-console repo (Vue.js)
         ↓
    npm run build
         ↓
    dist/ folder (compiled JS/CSS/HTML)
         ↓
    [rust-embed] crate
         ↓
    Embedded into lakekeeper Rust binary
         ↓
    Docker image contains everything
```

## 📋 Step-by-Step Process

### 1. Console Repository Structure

```
lakekeeper-console/
├── src/                    # Vue.js source code (your FgacManager.vue is here)
├── public/                 # Static assets
├── package.json            # NPM dependencies
├── vite.config.mts        # Build configuration
└── console-rs/            # Rust wrapper crate
    ├── Cargo.toml         # Defines the Rust crate
    ├── build.rs           # BUILD SCRIPT - THE MAGIC HAPPENS HERE
    └── src/lib.rs         # Rust code to serve embedded files
```

### 2. The Build Script (`console-rs/build.rs`)

**What it does during `cargo build`:**

1. **Copies entire Vue.js project** to `$OUT_DIR/node/`
   ```rust
   fs_extra::dir::copy(repo_dir, &node_root, ...)
   ```

2. **Runs `npm ci`** to install dependencies
   ```rust
   Command::new("bash").arg("cd {} && npm ci")
   ```

3. **Runs `npm run build-placeholder`** to compile Vue.js → static files
   ```rust
   Command::new("npm").args(["run", "build-placeholder"])
   ```

4. **Outputs to** `$OUT_DIR/node/dist/`
   - `index.html`
   - `assets/*.js`
   - `assets/*.css`
   - etc.

### 3. The Embedding (`console-rs/src/lib.rs`)

Uses the **rust-embed** crate to embed files at **compile time**:

```rust
#[derive(Embed)]
#[folder = "$OUT_DIR/node/dist"]  // ← Points to build output
struct LakekeeperConsole;
```

**This creates a Rust struct where:**
- All files in `dist/` are **embedded as binary data** in the Rust executable
- No external files needed at runtime!
- The binary contains the entire UI

### 4. Runtime Serving (`lakekeeper-bin/src/ui.rs`)

When lakekeeper runs, it serves these embedded files:

```rust
use lakekeeper_console::{get_file, LakekeeperConsoleConfig};

// Get embedded file
let file = get_file("index.html", &config)?;

// Serve to browser
Response::builder()
    .body(file.data.to_vec())
    .build()
```

### 5. Cargo Dependency Chain

**lakekeeper-bin/Cargo.toml:**
```toml
lakekeeper-console = { 
    git = "https://github.com/lakekeeper/console", 
    rev = "v0.10.1",  # ← Points to specific version
    optional = true 
}
```

When you run `cargo build`:
1. Cargo downloads console repo at tag `v0.10.1`
2. Runs `console-rs/build.rs` (which builds Vue.js)
3. Embeds compiled files into binary
4. Links into final executable

### 6. Docker Build Process

**docker-compose-build.yaml:**
```yaml
lakekeeper:
  build:
    context: ../../              # Root of lakekeeper-local
    dockerfile: docker/full.Dockerfile
```

**docker/full.Dockerfile:**
```dockerfile
# Stage 1: Build
FROM rust:1.87-slim-bookworm AS builder
RUN apt-get install nodejs npm  # ← Needed for console build
COPY . .
RUN cargo build --release --all-features --bin lakekeeper

# Stage 2: Runtime
FROM scratch
COPY --from=builder /app/target/release/lakekeeper /home/nonroot/lakekeeper
ENTRYPOINT ["/home/nonroot/lakekeeper"]
```

**During `docker build`:**
1. Installs Node.js (needed for npm)
2. Copies all source code
3. Runs `cargo build --release`
   - Downloads console from GitHub at `rev = "v0.10.1"`
   - Runs console's `build.rs`
   - Compiles Vue.js with npm
   - Embeds dist files into Rust binary
4. Copies binary to final image
5. **No separate UI files** - everything is in the binary!

## 🔑 Key Points

### ✅ What IS Included in Docker Image
- ✅ Compiled Rust binary (`/home/nonroot/lakekeeper`)
- ✅ Embedded Vue.js UI (inside the binary)
- ✅ All compiled JS/CSS/HTML files (embedded)

### ❌ What is NOT Included in Docker Image
- ❌ Vue.js source code (`.vue` files)
- ❌ Node.js or npm
- ❌ Separate UI files (everything is embedded)

## 🚨 The Problem: Your Changes Aren't Included!

### Current Situation

You made changes to:
```
/Users/anand.lonkar/code/lakekeeper/lakekeeper-console/src/components/FgacManager.vue
/Users/anand.lonkar/code/lakekeeper/lakekeeper-console/src/pages/warehouse/[id].namespace.[nsid].table.[tid].vue
```

**BUT** `lakekeeper-bin/Cargo.toml` points to:
```toml
lakekeeper-console = { 
    git = "https://github.com/lakekeeper/console", 
    rev = "v0.10.1"  # ← OLD VERSION, doesn't have your changes!
}
```

When you build the Docker image:
1. ✅ Your Rust changes (ui.rs proxy) ARE included
2. ❌ Your Vue.js changes (FgacManager.vue) are NOT included
3. It downloads v0.10.1 from GitHub (old version without FGAC tab)

## 🔧 How to Include Your Console Changes

### Option 1: Use Local Path (Quick Testing)

**Modify `lakekeeper-bin/Cargo.toml`:**
```toml
[dependencies]
lakekeeper-console = { 
    path = "../../../lakekeeper-console/console-rs",  # ← Local path
    optional = true 
}
```

Then rebuild:
```bash
cd examples/access-control-fgac
docker-compose -f docker-compose-build.yaml build
docker-compose up -d
```

**Pros:**
- ✅ Includes your local changes immediately
- ✅ Fast iteration for testing

**Cons:**
- ❌ Docker build context must include console repo
- ❌ Not suitable for production
- ❌ Need to adjust docker-compose context path

### Option 2: Publish New Console Version (Production)

1. **Commit your changes to lakekeeper-console:**
   ```bash
   cd /Users/anand.lonkar/code/lakekeeper/lakekeeper-console
   git add .
   git commit -m "feat: add FGAC management tab"
   ```

2. **Create a new branch or fork:**
   ```bash
   git checkout -b feature/fgac-tab
   git push origin feature/fgac-tab
   
   # OR if you have a fork:
   git remote add myfork https://github.com/YOUR_USERNAME/console.git
   git push myfork feature/fgac-tab
   ```

3. **Update `lakekeeper-bin/Cargo.toml` to use your branch:**
   ```toml
   lakekeeper-console = { 
       git = "https://github.com/YOUR_USERNAME/console", 
       branch = "feature/fgac-tab",
       optional = true 
   }
   ```

4. **Rebuild Docker image:**
   ```bash
   docker-compose -f docker-compose-build.yaml build
   ```

### Option 3: Create Git Tag (Cleanest)

1. **Tag your console changes:**
   ```bash
   cd /Users/anand.lonkar/code/lakekeeper/lakekeeper-console
   git tag v0.10.2-fgac
   git push origin v0.10.2-fgac
   ```

2. **Update Cargo.toml:**
   ```toml
   lakekeeper-console = { 
       git = "https://github.com/lakekeeper/console", 
       rev = "v0.10.2-fgac",
       optional = true 
   }
   ```

## 🎯 Recommended Approach for Testing

### Quick Test Setup

1. **Create a local Dockerfile that includes both repos:**

```dockerfile
# docker/test-local.Dockerfile
FROM rust:1.87-slim-bookworm AS builder

RUN apt-get update && apt-get install -y \
    cmake curl build-essential libpq-dev pkg-config make perl wget zip unzip nodejs npm

WORKDIR /app

# Copy lakekeeper source
COPY lakekeeper-local/ ./lakekeeper-local/

# Copy console source (your modified version)
COPY lakekeeper-console/ ./lakekeeper-console/

# Build lakekeeper with local console
WORKDIR /app/lakekeeper-local
RUN cargo build --release --all-features --bin lakekeeper

FROM gcr.io/distroless/cc-debian12:nonroot
COPY --from=builder /app/lakekeeper-local/target/release/lakekeeper /home/nonroot/lakekeeper
ENTRYPOINT ["/home/nonroot/lakekeeper"]
```

2. **Update docker-compose-build.yaml:**

```yaml
lakekeeper:
  build:
    context: ../../..  # Parent of both repos
    dockerfile: lakekeeper-local/docker/test-local.Dockerfile
```

3. **Modify lakekeeper-local/crates/lakekeeper-bin/Cargo.toml:**

```toml
lakekeeper-console = { 
    path = "../../../lakekeeper-console/console-rs"
}
```

This way, both your Rust and Vue.js changes are included!

## 📊 Summary

| Component | Location | Included in Docker? |
|-----------|----------|---------------------|
| Rust source (ui.rs) | lakekeeper-local/crates/ | ✅ Yes (from local files) |
| Vue.js source (FgacManager.vue) | lakekeeper-console/src/ | ❌ No (downloads from GitHub) |
| Compiled UI (dist/) | Inside Rust binary | ✅ Yes (but from GitHub v0.10.1) |
| Runtime dependencies | - | ❌ No (embedded at build time) |

**To include your console changes, you must either:**
- Use a local path dependency, OR
- Push to GitHub and update the rev/branch in Cargo.toml
