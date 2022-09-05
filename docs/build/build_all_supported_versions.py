#! /usr/bin/env python3
import argparse
import emoji
import git
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

# Set git repository details
development_branch = "develop"
earliest_supported_release = "v3.4.0"

# --- Parse arguments ---
parser = argparse.ArgumentParser(
    prog="python build_docs_all.py",
    description="Build documentation for all supported versions",
)
parser.add_argument(
    "-o", "--output-dir", help="Directory to store built documentation", required=True
)
parser.add_argument(
    "-s",
    "--skip-pdfs",
    action="store_true",
    help="Skip building PDFs (use only for faster testing)",
)
args = parser.parse_args()
skip_pdfs = args.skip_pdfs

# Create output directory
combined_output_dir = pathlib.Path(args.output_dir).resolve()
if combined_output_dir.exists():
    shutil.rmtree(combined_output_dir)
combined_output_dir.mkdir(parents=True, exist_ok=True)

# Necessary directories
temp_dir = tempfile.TemporaryDirectory()
build_dir = pathlib.Path(__file__).parent.resolve()
docs_dir = build_dir.parent
build_output_dir = docs_dir / "_output"
config_backup_dir = pathlib.Path(temp_dir.name) / "build_config"

# Get git repository details
repo = git.Repo(search_parent_directories=True)
repo_name = repo.remotes.origin.url.split(".git")[0].split("/")[-1]

# Load all release since earliest_supported_release
releases = sorted((t.name for t in repo.tags), reverse=True)
supported_versions = (
    releases[: releases.index(earliest_supported_release) + 1]
    + [development_branch]
)
default_version = supported_versions[0]  # Latest stable release
current_version = (
    [tag for tag in repo.tags if tag.commit == repo.head.commit]
    + [branch for branch in repo.branches if branch.commit == repo.head.commit]
)[0].name  # Tag or branch name

# --- Ensure local repo is clean --
if repo.is_dirty(untracked_files=True):
    print(
        "Repo is not clean. Run 'git status' and ensure repo is clean before rerunning this script."
    )
    exit(1)

# --- Backup documentastion build configuration ---
# Backup Sphinx docs build configuration from current branch to ensure
# consistent style and navigation elements for docs across all versions
# NOTE: copytree() requires the destination directory does not exist
# This is why we target a subfolder of the TemporaryDirectory we create
# earlier as the config backup directory
print(f"Backing up build config to: '{config_backup_dir}'")
shutil.copytree(build_dir, config_backup_dir)

# --- Build docs for all supported versions ---
print(f"Building docs for all supported versions: {supported_versions}")
print(f"Default version: {default_version}")


# Flag to bypass Jekyll processing since this is a static html site
open(combined_output_dir / ".nojekyll", "w+").close()

# Build docs for each branch
for version in supported_versions:
    print(f"{emoji.emojize(':hourglass:', language='alias')} Generating docs for version '{version}'...")

    try:
        # Checkout repo at this version
        repo.git.checkout(version)

        # Restore Sphinx docs build configuration from backup for consistent style,
        # clearing any existing build configuration directory content first.
        if os.path.exists(build_dir):
            shutil.rmtree(build_dir)
        shutil.copytree(config_backup_dir, build_dir)

        # Use the first of these files that exists as the index:
        # - index.md
        # - README.md
        # - DSG-user-documentation.md
        # - An empty index.md
        target = docs_dir / "index.md"
        if target.is_file():
            # Use existing index file. Nothing to do.
            pass
        elif (source := docs_dir / "README.md").is_file():
            # Use docs README
            shutil.move(source, target)
        elif (source := docs_dir / "DSG-user-documentation.md").is_file():
            # Use docs DSG user documentation
            shutil.move(source, target)
        else:
            # Use empty index file
            shutil.copy(build_dir / "meta" / "index.empty.md", target)

        # Clean the output directory
        subprocess.run(
            ["make", "clean"],
            cwd=docs_dir,
            check=True,
        )
        # Build docs for this version
        build_commands = ["make", "html"]
        if not skip_pdfs:
            build_commands.append("pdf")
        subprocess.run(
            build_commands,
            cwd=docs_dir,
            check=True,
        )
        # Store docs in the output directory
        shutil.copytree(build_output_dir, combined_output_dir / version)
        shutil.rmtree(build_output_dir)

    except subprocess.CalledProcessError:
        print(f"Error encountered during build for version '{version}'")
        raise
    else:
        print(f"{emoji.emojize(':sparkles:', language='alias')} Successfully built docs for version '{version}'")
    finally:
        # Revert any changes made to current branch
        print(f"Reverting changes made to '{version}'")
        repo.git.reset("--hard", "HEAD")
        repo.git.clean("-fd")

# Write top-level index file to redirect to default version of docs
with open(os.path.join(docs_dir, "build", "meta", "index.html"), "r") as file:
    filedata = file.read()
filedata = filedata.replace("{{latest_stable}}", default_version)
with open(os.path.join(combined_output_dir, "index.html"), "w+") as file:
    file.write(filedata)

# -- Restore original branch and copy docs to specified output directory --
print(f"Documentation builds complete for all versions: {supported_versions}")
# Checkout original branch
print(f"Restoring original '{current_branch}' branch.")
repo.git.checkout(current_branch)
temp_dir.cleanup()

# Check that all versions have built
n_failures = 0
for version in supported_versions:
    if (combined_output_dir / version / "index.html").is_file():
        print(f"{emoji.emojize(':white_check_mark:', language='alias')} {version} documentation built successfully")
    else:
        print(f"{emoji.emojize(':x:', language='alias')} {version} documentation failed to build!")
        n_failures += 1
    if n_failures:
        sys.exit(1)
