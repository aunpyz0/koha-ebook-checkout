All agents working in this repository must follow this rule:

- Every template file ending in `.tt` must be executable.

Possible Koha plugin hooks and entry points to refer to during future plugin
development, based on the Kitchen Sink plugin:

- `new`: Minimum code required for a plugin's `new` method. Add plugin metadata so the base class can access it, then call the base class `new` method.
- `report`: A plugin with this subroutine can run a report. Reports can output HTML, CSV, or other report data, and complex reports should split control flow into helper methods.
- `tool`: A plugin with this subroutine can run a tool. Tools are semantically different from reports; generally, plugins that modify the Koha database should be tools.
- `admin`: A plugin with this subroutine has functionality available to Koha librarians with administrative privileges. Admin plugins display on the admin page and work similarly to tools.
- `to_marc`: Converts some type of file to MARC for use from the stage records for import tool.
- `opac_online_payment`: Returns true when the plugin can process OPAC online payments and the feature is enabled.
- `opac_online_payment_begin`: Starts the payment process. It may display a form for the patron or redirect directly to a payment service.
- `opac_online_payment_end`: Ends the payment process and should display success or failure details.
- `opac_head`: Adds CSS to the OPAC. Return CSS wrapped in `<style>` tags, or include external CSS as needed.
- `opac_js`: Adds JavaScript to the OPAC. Return JavaScript wrapped in `<script>` tags, or include external JavaScript as needed.
- `intranet_head`: Adds CSS to the staff intranet. Return CSS wrapped in `<style>` tags, or include external CSS as needed.
- `intranet_js`: Adds JavaScript to the staff intranet. Return JavaScript wrapped in `<script>` tags, or include external JavaScript as needed.
- `intranet_catalog_biblio_enhancements_toolbar_button`: Adds HTML elements, usually a button, to the staff catalogue toolbar.
- `configure`: Adds plugin settings/configuration. This can contain all configuration logic or delegate to helper methods.
- `install`: Runs when the plugin is first installed. Use it for database tables or other setup and return true on success.
- `upgrade`: Runs when a newer plugin version is installed over an older version.
- `uninstall`: Runs just before plugin files are deleted. Use it to clean up plugin-created resources.
- `schedule_greets`: Kitchen Sink helper that schedules greeter background jobs; use as an example of delegating tool behavior to a helper.
- `api_routes`: Required when the plugin implements API routes. Return valid OpenAPI 2.0 paths serialized as a hashref.
- `api_namespace`: Returns the plugin API namespace.
- `static_routes`: Returns static API route specs.
- `opac_detail_xslt_variables`: Hook for injecting variables into the OPAC detail XSLT.
- `opac_results_xslt_variables`: Hook for injecting variables into the OPAC results XSLT.
- `cronjob_nightly`: Hook for running plugin code from a nightly cron job.
- `before_send_messages`: Hook that runs right before the message queue is processed in `process_message_queue.pl`.
- `item_barcode_transform`: Hook that transforms input anywhere item barcodes are scanned.
- `patron_barcode_transform`: Hook that transforms input anywhere patron barcodes are scanned.
- `intranet_catalog_biblio_tab`: Hook that adds tabs with plugin-created content to the staff record details page.
- `background_tasks`: Hook used to register new background job types.
- `transform_prepared_letter`: Hook used to modify prepared slips and notices.
