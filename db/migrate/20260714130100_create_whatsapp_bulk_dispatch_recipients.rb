class CreateWhatsappBulkDispatchRecipients < ActiveRecord::Migration[7.0]
  def change
    create_table :whatsapp_bulk_dispatch_recipients do |t|
      # index: false — the two composite indexes below both lead with this column, so a plain
      # single-column index here would just be redundant (and its default name is too long for
      # Postgres' 63-char limit anyway).
      t.references :whatsapp_bulk_dispatch, null: false, index: false
      t.string :phone_number, null: false
      t.jsonb :variables, default: {}
      t.integer :status, default: 0, null: false
      t.string :error_message
      t.datetime :sent_at

      t.timestamps
    end

    add_index :whatsapp_bulk_dispatch_recipients, [:whatsapp_bulk_dispatch_id, :status],
              name: 'index_wa_bulk_dispatch_recipients_on_dispatch_and_status'
    add_index :whatsapp_bulk_dispatch_recipients, [:whatsapp_bulk_dispatch_id, :phone_number],
              unique: true, name: 'index_wa_bulk_dispatch_recipients_on_dispatch_and_phone'
  end
end
