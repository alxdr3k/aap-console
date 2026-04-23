class AddUniqueIndexToProvisioningSteps < ActiveRecord::Migration[8.1]
  def change
    add_index :provisioning_steps, [:provisioning_job_id, :name],
              unique: true,
              name: "index_provisioning_steps_on_job_id_and_name"
  end
end
