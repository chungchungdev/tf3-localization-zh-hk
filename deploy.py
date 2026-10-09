import shutil
import sys
import click
import polib
from datetime import datetime
from loguru import logger
from pathlib import Path
from rich.console import Console

console = Console()


def compile_pofile(po_path: str | Path, mo_path: str | Path) -> None:
    """
    Compile .po to .mo file.
    Treat all fuzzy entires as translated.
    """
    logger.trace(f"load {po_path}")
    po = polib.pofile(str(po_path))
    logger.trace(f"\tremoving fuzzy")
    for entry in po:
        if "fuzzy" in entry.flags:
            entry.flags.remove("fuzzy")

    po.save_as_mofile(str(mo_path))
    logger.trace(f"saving po to {mo_path}")
    logger.debug(f"compiled {po_path} to {mo_path}")


def compile_pofiles(directory: str | Path) -> list[Path]:
    """Recursively finds all .po files in directory and compiles each to an .mo file

    in the exact same folder alongside the original .po file.

    Returns:
        List of created .mo file paths.
    """
    root_dir = Path(directory).resolve()

    if not root_dir.is_dir():
        raise ValueError(f"Directory does not exist: {root_dir}")

    compiled_mo_files: list[Path] = []

    # Recursively traverse all .po files in root_dir
    for po_path in root_dir.rglob("*.po"):
        # Output file path in the same directory with .mo extension
        mo_path = po_path.with_suffix(".mo")

        compile_pofile(po_path, mo_path)
        compiled_mo_files.append(mo_path)

    logger.debug(f"Compiled {len(compiled_mo_files)} file(s).")

    return compiled_mo_files


def backup_to_zip(folder_path: str | Path) -> Path:
    """Zips the contents of folder_path into a file named <folder_name>_<timestamp>.zip

    The zip file is created in the same directory where folder_path is located.
    """
    target = Path(folder_path).resolve()

    if not target.is_dir():
        raise ValueError(f"Target path is not a valid directory: {target}")

    # Generate timestamp format: YYYYMMDD_HHMMSS
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")

    # Construct zip path: /parent/dir/<folder_name>_<timestamp>
    output_filename = f"{target.name}_{timestamp}"
    output_zip_path = target.parent / output_filename

    # shutil.make_archive expects base_name without the .zip extension
    archive_path = shutil.make_archive(
        base_name=str(output_zip_path),
        format="zip",
        root_dir=target,  # Zips folder contents directly, not the root folder itself
    )

    logger.debug(f"Backup created: {output_zip_path}.zip")

    return Path(archive_path)


def copy_mo_files_tree(folder_a: str | Path, folder_b: str | Path) -> list[Path]:
    """Finds all .mo files in folder_a and copies them to the exact corresponding

    relative paths in folder_b (creating directories as needed and replacing existing files).

    Returns:
        List of target paths where .mo files were copied in folder_b.
    """
    src_dir = Path(folder_a).resolve()
    dst_dir = Path(folder_b).resolve()

    if not src_dir.is_dir():
        raise ValueError(
            f"Source folder does not exist or is not a directory: {src_dir}"
        )

    copied_files: list[Path] = []

    # Find all .mo files in folderA recursively
    for mo_src in src_dir.rglob("*.mo"):
        # Calculate the relative path from folderA
        relative_path = mo_src.relative_to(src_dir)

        # Construct destination path in folderB
        mo_dst = dst_dir / relative_path

        # Create parent directories in folderB if they don't exist
        mo_dst.parent.mkdir(parents=True, exist_ok=True)
        logger.trace(f"Copying {mo_src} to {mo_dst}")
        # Copy file and preserve metadata (overwrites if target already exists)
        shutil.copy2(mo_src, mo_dst)
        copied_files.append(mo_dst)

    return copied_files


def copy_to_staging_area(src: str | Path, dst: str | Path) -> None:
    """
    Copies all contents from src directory to dst directory.
    Creates dst directory if it does not exist.
    """
    src_path = Path(src)
    dst_path = Path(dst)

    if not src_path.is_dir():
        raise ValueError(f"Source path is not a valid directory: {src_path}")

    logger.debug(f"Copying mod content to {dst}")

    # shutil.copytree automatically creates dst_path (and parents) if it doesn't exist
    shutil.copytree(src_path, dst_path, dirs_exist_ok=True)


@click.command
@click.argument("staging_area_path", type=click.Path(exists=True, file_okay=False))
@click.option("-b", "--backup", is_flag=True)
@click.option("-v", "--verbose", is_flag=True)
def deploy(staging_area_path, backup, verbose):
    # Set the log level
    logger.remove()
    if verbose:
        logger.add(sys.stderr, level="DEBUG")
    else:
        logger.add(sys.stderr, level="INFO")

    # steps = [
    #     ("Compiling .mo files...", "Files compiled successfully"),
    #     ("Backing up previous version...", "Backup completed"),
    #     ("Copying mod files...", "All files copied"),
    # ]

    compile_pofiles(Path("translation/zh_HK"))
    copy_mo_files_tree(Path("translation/zh_HK"), Path("mod/strings/zh_HK"))

    mod_folder_path = Path(staging_area_path) / "tf3_localization_zh_hk"

    if backup:
        backup_to_zip(mod_folder_path)

    copy_to_staging_area(Path("mod"), mod_folder_path)


if __name__ == "__main__":
    deploy()
