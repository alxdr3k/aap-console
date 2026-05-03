class AddDestroyFinalizerReservedUntilToOrganizations < ActiveRecord::Migration[8.1]
  def change
    add_column :organizations, :destroy_finalizer_reserved_until, :datetime
  end
end
