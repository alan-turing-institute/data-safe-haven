import argparse
from codecs import ignore_errors
import importlib.util
import os
import pathlib
import shutil
import subprocess
import tempfile

# Reliably import local module, no matter how python script is called
current_file_dir = os.path.dirname(os.path.realpath(__file__))
spec=importlib.util.spec_from_file_location("repo_info",
    os.path.join(current_file_dir, "repo_info.py"))
repo_info = importlib.util.module_from_spec(spec)
spec.loader.exec_module(repo_info)

# --- Parse arguments ---
parser = argparse.ArgumentParser(
    prog="python build_docs_all.py",
    description="Build documentation for all supported versions")
parser.add_argument('--output-dir',
    help='Directory to store built documentation')
parser.add_argument('--skip-pdfs', action='store_true',
    help='Skip building PDFs (use only for faster testing)')
args = parser.parse_args()
final_build_output_dir = args.output_dir
skip_pdfs = args.skip_pdfs
temp_dir = tempfile.TemporaryDirectory()


# --- Ensure local repo is clean --
if repo_info.repo.is_dirty(untracked_files=True):
    print("Repo is not clean. Run 'git status' and ensure repo is clean before rerunning this script.")
    exit(1)

# --- Backup documentastion build configuration ---
# Backup Sphinx docs build configuration from current branch to ensure
# consistent style and navigation elements for docs across all versions
# NOTE: copytree() requires the destination directory does not exist
# This is why we target a subfolder of the TemporaryDirectory we create
# earlier as the config backup directory
build_config_backup_path = os.path.join(temp_dir.name, "build_config")
print(f"Backing up build config to: '{build_config_backup_path}'")
shutil.copytree('./docs/build/', build_config_backup_path)


# --- Build docs for all supported versions ---
print(f"Building docs for all supported versions: {repo_info.supported_versions}")
print(f"Default version: {repo_info.default_version}")

# Create temporary build directory separate to repo so it is not overwritten
# when we check out each version branch
temp_build_path = os.path.join(temp_dir.name, "_output")
if os.path.exists(temp_build_path):
    shutil.rmtree(temp_build_path)
else:
    os.makedirs(temp_build_path)
print(f"Temporary build directory: '{temp_build_path}'")

# Flag to bypass Jekyll processing (we're buildign a static html site)
open(os.path.join(temp_build_path, ".nojekyll"), 'w+').close()

# Build docs for each branch
original_branch = repo_info.repo.active_branch
git = repo_info.repo.git

docs_dir = "./docs"
branch_build_config_dir = "./docs/build"

for version in repo_info.supported_versions:
    print(f"Generating docs for version '{version}'...")

    try:
        # Checkout repo at this version
        git.checkout(version)

        # Restore Sphinx docs build configuration from backup for consistent style,
        # clearing any existing build configuration directory content first. 
        if(os.path.exists(branch_build_config_dir)):
            shutil.rmtree(branch_build_config_dir)
        shutil.copytree(build_config_backup_path, branch_build_config_dir)

        # Use the first of these files that exists as the index:
        # - index.md
        # - README.md
        # - DSG-user-documentation.md
        # - An empty index.md
        if os.path.exists(os.path.join(docs_dir, "index.md")):
            # Use existing incex file. Nothing to do.
            True
        elif os.path.exists(os.path.join(docs_dir, "README.md")):
            # Use docs README
            shutil.move(os.path.join(docs_dir, "README.md"),os.path.join(docs_dir, "index.md"))
        elif os.path.exists(os.path.join(docs_dir, "DSG-user-documentation.md")):
            # Use docs DSG user documentation
            shutil.move(os.path.join(docs_dir, "DSG-user-documentation.md"),os.path.join(docs_dir, "index.md"))
        else:
            # Use empty index file
            shutil.copy(os.path.join(branch_build_config_dir,"meta","index.empty.md"),os.path.join(docs_dir,"index.md"))

        # Build docs for this version
        print(os.path.join(current_file_dir, "build_docs_instance.sh"))
        if (version == repo_info.default_version and not(skip_pdfs)):
            pdf_flag = "-p"
        else:
            pdf_flag = ""
        subprocess.run([os.path.join(current_file_dir, "build_docs_instance.sh"), "-d",temp_build_path, "-n", version, pdf_flag])
    except:
        # In case of encountring an error:
        print(f"Error encountered during build for version '{version}'. Restoring original branch '{original_branch}'")
        # - Revert any changes made to current branch
        git.reset("--hard", "HEAD")
        git.clean("-fd")   
        # - Checkout original branch
        print(f"Restoring original '{original_branch}' branch.")
        git.checkout(original_branch)
        raise

# Write top-level index file to redirect to default version of docs
with open(os.path.join(docs_dir, "build", "meta", "index.html"), "r") as file:
    filedata = file.read()
filedata = filedata.replace("{{latest_stable}}", repo_info.default_version)
with open(os.path.join(temp_build_path, "index.html"),"w+") as file:
    file.write(filedata)

# -- Restore original branch and copy docs to specified output directory --
print(f"Documentation builds complete for all versions: {repo_info.supported_versions}")
# Checkout original branch
print(f"Restoring original '{original_branch}' branch.")
git.checkout(original_branch)
# Copy build documentaton to specified out put directory
print(f"Copying build documentation to '{final_build_output_dir}'")
shutil.copytree(temp_build_path, final_build_output_dir)
print("Done.")
