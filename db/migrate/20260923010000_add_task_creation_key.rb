class AddTaskCreationKey < ActiveRecord::Migration[8.1]
  def change
    add_column :tasks, :creation_key, :string
    add_index :tasks, %i[project_id task_type_id creation_key], unique: true,
      where: "creation_key IS NOT NULL", name: "index_tasks_on_scoped_creation_key"
  end
end
