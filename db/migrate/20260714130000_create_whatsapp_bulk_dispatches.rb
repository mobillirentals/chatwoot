class CreateWhatsappBulkDispatches < ActiveRecord::Migration[7.0]
  def change
    create_table :whatsapp_bulk_dispatches do |t|
      # No foreign_key: true — this schema indexes references but doesn't enforce DB-level FKs
      # (see campaigns/data_imports for the same convention).
      t.references :account, null: false
      t.references :inbox, null: false
      t.references :sender
      t.string :title, null: false
      t.integer :status, default: 0, null: false
      t.string :template_name
      t.string :template_namespace
      t.string :template_language
      t.jsonb :column_mapping, default: {}
      t.datetime :scheduled_at
      t.integer :total_recipients, default: 0
      t.integer :sent_count, default: 0
      t.integer :failed_count, default: 0

      t.timestamps
    end
  end
end
