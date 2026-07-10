module Trashable
  extend ActiveSupport::Concern

  included do
    default_scope { where(deleted_at: nil) }

    scope :trashed, -> { unscope(where: :deleted_at).where.not(deleted_at: nil) }
    scope :with_trashed, -> { unscope(where: :deleted_at) }
  end

  def trash!
    update!(deleted_at: Time.current)
  end

  def restore!
    update!(deleted_at: nil)
  end

  def trashed?
    deleted_at.present?
  end
end
