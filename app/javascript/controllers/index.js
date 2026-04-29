import { application } from "controllers/application"
import FlashController from "controllers/flash_controller"
import RolePermissionsController from "controllers/role_permissions_controller"
import UserSearchController from "controllers/user_search_controller"

application.register("flash", FlashController)
application.register("role-permissions", RolePermissionsController)
application.register("user-search", UserSearchController)
