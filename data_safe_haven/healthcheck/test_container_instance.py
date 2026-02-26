from data_safe_haven.external import AzureContainerInstance


class TestContainerInstance:

    def test_container_instance(
        self,
        azure_container_instance: AzureContainerInstance,
    ) -> None:
        assert azure_container_instance.current_ip_address is not None
