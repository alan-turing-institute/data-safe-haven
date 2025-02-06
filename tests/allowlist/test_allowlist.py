from pytest import fixture

from data_safe_haven.allowlist import Allowlist
from data_safe_haven.external import AzureSdk
from data_safe_haven.provisioning.sre_provisioning_manager import SREProjectManager
from data_safe_haven.types import AllowlistRepository


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


class TestAllowlist:
    def test_from_remote(
        self,
        mocker,
        context,
        sre_project_manager,
        mock_project_output,
    ) -> None:

        repository = AllowlistRepository.CRAN
        mocker.patch.object(
            SREProjectManager,
            "output",
            wraps=mock_project_output,
        )
        mocker.patch.object(
            AzureSdk,
            "download_share_file",
            return_value="tidyverse\ndplyr\nnumpy",
        )
        result = Allowlist.from_remote(
            context=context,
            sre_stack=sre_project_manager,
            repository=repository,
        ).allowlist
        assert "dplyr" in result

    def test_remote_exists(
        self, mocker, context, sre_project_manager, mock_project_output
    ) -> None:
        mocker.patch.object(
            AzureSdk,
            "file_share_exists",
            return_value=True,
        )
        mocker.patch.object(
            SREProjectManager,
            "output",
            wraps=mock_project_output,
        )

        exists = Allowlist.remote_exists(
            context,
            sre_stack=sre_project_manager,
            repository=AllowlistRepository.CRAN,
        )

        assert isinstance(exists, bool)
        assert exists

    def test_remote_diff(
        self,
        mocker,
        context,
        sre_project_manager,
        mock_project_output,
    ) -> None:
        mocker.patch.object(
            SREProjectManager,
            "output",
            wraps=mock_project_output,
        )
        mocker.patch.object(
            AzureSdk, "download_share_file", return_value="tidyverse\ndplyr\nnumpy"
        )

        local_allowlist = Allowlist(
            sre_stack=sre_project_manager,
            repository=AllowlistRepository.CRAN,
            allowlist="tidyverse\ndplyr\nnumpy\npandas",
        )
        remote_allowlist = Allowlist.from_remote(
            context=context,
            sre_stack=sre_project_manager,
            repository=AllowlistRepository.CRAN,
        )

        diff = remote_allowlist.diff(local_allowlist)

        assert isinstance(diff, list)
        assert "+pandas" in diff

    def test_remote_diff_no_change(
        self,
        mocker,
        context,
        sre_project_manager,
        mock_project_output,
    ) -> None:
        mocker.patch.object(
            SREProjectManager,
            "output",
            wraps=mock_project_output,
        )
        mocker.patch.object(
            AzureSdk, "download_share_file", return_value="tidyverse\ndplyr\nnumpy"
        )
        local_allowlist = Allowlist(
            sre_stack=sre_project_manager,
            repository=AllowlistRepository.CRAN,
            allowlist="tidyverse\ndplyr\nnumpy",
        )
        remote_allowlist = Allowlist.from_remote(
            context=context,
            sre_stack=sre_project_manager,
            repository=AllowlistRepository.CRAN,
        )

        diff = remote_allowlist.diff(local_allowlist)

        assert isinstance(diff, list)
        assert not diff
