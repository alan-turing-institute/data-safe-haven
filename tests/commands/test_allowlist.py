from pytest import fixture, mark

from data_safe_haven.allowlist import Allowlist
from data_safe_haven.commands.allowlist import allowlist_command_group
from data_safe_haven.config import SREConfig
from data_safe_haven.external import AzureSdk
from data_safe_haven.infrastructure import SREProjectManager
from data_safe_haven.types import AllowlistRepository


@fixture
def mock_allowlist(mocker, sre_project_manager, mock_project_output) -> Allowlist:
    mocker.patch.object(
        SREProjectManager,
        "output",
        wraps=mock_project_output,
    )
    allow = Allowlist(
        repository=AllowlistRepository.CRAN,
        sre_stack=sre_project_manager,
        allowlist="tidyverse\ndplyr\nnumpy",
    )
    return allow


@fixture
def allowlist_file(mock_allowlist, tmp_path):
    allowlist_file_path = tmp_path / "allowlist.txt"
    with open(allowlist_file_path, "w") as f:
        f.write(mock_allowlist.allowlist)
    return allowlist_file_path


@fixture
def mock_project_output(request):
    if request == "allowlist_share_filenames":
        return {
            "cran": "cran.allowlist",
            "pypi": "pypi.allowlist",
        }
    elif request == "data":
        return {"storage_account_data_configuration_name": "test"}
    elif request == "sre_resource_group":
        return "test"


class TestShowAllowlist:
    def test_show(
        self,
        mocker,
        runner,
        mock_azuresdk_get_credential,  # noqa: ARG002
        mock_azuresdk_get_subscription,  # noqa: ARG002
        mock_sre_config_from_remote,  # noqa: ARG002
        mock_pulumi_config_no_key_from_remote,  # noqa: ARG002,
        mock_allowlist,
    ) -> None:
        sre_name = "sandbox"
        repository = "cran"
        mocker.patch.object(Allowlist, "from_remote", return_value=mock_allowlist)
        result = runner.invoke(
            allowlist_command_group,
            ["show", sre_name, repository],
        )
        assert result.exit_code == 0
        assert "tidyverse\ndplyr\nnumpy" in result.output

    def test_show_no_repositories(
        self,
        mocker,
        runner,
        mock_azuresdk_get_credential,  # noqa: ARG002
        mock_azuresdk_get_subscription,  # noqa: ARG002
        # mock_sre_config_from_remote,
        sre_config_any_packages,
        mock_pulumi_config_no_key_from_remote,  # noqa: ARG002,
        mock_allowlist,
    ) -> None:
        sre_name = "sandbox"
        repository = "cran"
        mocker.patch.object(
            SREConfig, "from_remote_by_name", return_value=sre_config_any_packages
        )
        mocker.patch.object(Allowlist, "from_remote", return_value=mock_allowlist)
        result = runner.invoke(
            allowlist_command_group,
            ["show", sre_name, repository],
        )
        assert result.exit_code == 0
        assert "required" in result.output


class TestTemplateAllowlist:
    @mark.parametrize(
        "repository",
        [
            "cran",
            "pypi",
        ],
    )
    def test_template(self, runner, repository) -> None:

        result = runner.invoke(
            allowlist_command_group,
            ["template", repository],
        )
        assert result.exit_code == 0
        if repository == "cran":
            assert "DBI\nMASS" in result.output
        elif repository == "pypi":
            assert "numpy\npackaging" in result.output


class TestUploadAllowlist:
    @mark.parametrize(
        "repository",
        [
            "cran",
            "pypi",
        ],
    )
    def test_upload_no_remote(
        self,
        mocker,
        runner,
        repository,
        allowlist_file,
        mock_azuresdk_get_subscription,  # noqa: ARG002
        mock_pulumi_config_no_key_from_remote,  # noqa: ARG002
        mock_sre_config_from_remote,  # noqa: ARG002
        mock_azuresdk_get_credential,  # noqa: ARG002
        mock_project_output,
    ) -> None:
        sre_name = "sandbox"
        mocker.patch.object(
            SREProjectManager,
            "output",
            wraps=mock_project_output,
        )

        mocker.patch.object(Allowlist, "remote_exists", return_value=False)
        mocker.patch.object(AzureSdk, "upload_file_share", return_value=None)

        result = runner.invoke(
            allowlist_command_group,
            ["upload", sre_name, str(allowlist_file), repository],
        )
        assert result.exit_code == 0

    @mark.parametrize(
        "repository",
        [
            "cran",
            "pypi",
        ],
    )
    def test_upload_remote_exists_no_diff(
        self,
        mocker,
        runner,
        repository,
        allowlist_file,
        mock_allowlist,
        mock_azuresdk_get_subscription,  # noqa: ARG002
        mock_project_output,
        mock_pulumi_config_no_key_from_remote,  # noqa: ARG002
        mock_sre_config_from_remote,  # noqa: ARG002
        mock_azuresdk_get_credential,  # noqa: ARG002
    ) -> None:
        sre_name = "sandbox"
        mocker.patch.object(
            SREProjectManager,
            "output",
            wraps=mock_project_output,
        )
        mocker.patch.object(Allowlist, "remote_exists", return_value=True)
        mocker.patch.object(Allowlist, "from_remote", return_value=mock_allowlist)
        mocker.patch.object(Allowlist, "diff", return_value=[])

        result = runner.invoke(
            allowlist_command_group,
            ["upload", sre_name, str(allowlist_file), repository],
        )
        assert result.exit_code == 0
        assert "No changes, won't upload allowlist." in result.output

    def test_upload_remote_exists_with_diff(
        self,
        mocker,
        runner,
        allowlist_file,
        mock_allowlist,
        mock_azuresdk_get_subscription,  # noqa: ARG002
        mock_pulumi_config_no_key_from_remote,  # noqa: ARG002
        mock_sre_config_from_remote,  # noqa: ARG002
        mock_azuresdk_get_credential,  # noqa: ARG002
        mock_project_output,
    ) -> None:
        sre_name = "sandbox"
        repository = "cran"
        mocker.patch.object(
            SREProjectManager,
            "output",
            wraps=mock_project_output,
        )
        mocker.patch.object(AzureSdk, "upload_file_share", return_value=None)
        mocker.patch.object(Allowlist, "remote_exists", return_value=True)
        mocker.patch.object(Allowlist, "from_remote", return_value=mock_allowlist)
        mocker.patch.object(Allowlist, "diff", return_value=["-numpy", "+pandas"])

        result = runner.invoke(
            allowlist_command_group,
            ["upload", sre_name, str(allowlist_file), repository],
            input="y\n",
        )

        assert "-numpy" in result.output
        assert result.exit_code == 0
        assert "An allowlist already exists" in result.output
        assert "Uploading allowlist for CRAN to sandbox" in result.output
