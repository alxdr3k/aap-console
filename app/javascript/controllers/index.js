import { application } from "controllers/application"
import DirtyTrackerController from "controllers/dirty_tracker_controller"
import FlashController from "controllers/flash_controller"
import ProvisioningController from "controllers/provisioning_controller"
import RolePermissionsController from "controllers/role_permissions_controller"
import SecretRevealController from "controllers/secret_reveal_controller"
import UriListController from "controllers/uri_list_controller"
import UserSearchController from "controllers/user_search_controller"

application.register("dirty-tracker", DirtyTrackerController)
application.register("flash", FlashController)
application.register("provisioning", ProvisioningController)
application.register("role-permissions", RolePermissionsController)
application.register("secret-reveal", SecretRevealController)
application.register("uri-list", UriListController)
application.register("user-search", UserSearchController)
