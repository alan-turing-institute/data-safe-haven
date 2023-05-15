````{error}
If you see a message `You need to add the following NS records to the parent DNS system for...` you will need to manually add the specified NS records to the parent's DNS system, as follows:

<details><summary><b>Manual DNS configuration instructions</b></summary>

![Portal: one minute](https://img.shields.io/static/v1?style=for-the-badge&logo=microsoft-azure&label=portal&color=blue&message=one%20minute)

- To find the required values for the NS records on the portal, click `All resources` in the far left panel, search for "DNS Zone" and locate the DNS Zone with SRE's domain. The NS record will list 4 Azure name servers.
  ```{image} deploy_shm/shm_subdomain_ns.png
  :alt: SHM NS record
  :align: center
  ```
- Duplicate these records to the parent DNS system as follows:
  - If the parent domain has an Azure DNS Zone, create an NS record set in this zone.
    - The name should be set to the subdomain (e.g. `sandbox` ) or `@` if using a custom domain, and the values duplicated from above.
    - For example, for a new subdomain `sandbox.testa.dsgroupdev.co.uk` , duplicate the NS records from the Azure DNS Zone `sandbox.testa.dsgroupdev.co.uk` to the Azure DNS Zone for `testa.dsgroupdev.co.uk`, by creating a record set with name `sandbox`.
      ```{image} deploy_sre/sre_subdomain_ns.png
      :alt: SRE NS record
      :align: center
      ```
  - If the parent domain is outside of Azure, create NS records in the registrar for the new domain with the same value as the NS records in the new Azure DNS Zone for the domain.
</details>
````
