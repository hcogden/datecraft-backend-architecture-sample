# == Schema Information
#
# Table name: user_profiles
#
#  id                  :bigint           not null, primary key
#  allergies           :text             default([])
#  budget              :string
#  dietary_preferences :text
#  duration_preference :integer          default("flexible")
#  interests           :text
#  ip_address          :string
#  location            :string
#  name                :string
#  preferred_date      :datetime
#  temporary           :boolean          default(FALSE)
#  time_preference     :integer          default("anytime")
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  user_id             :bigint
#
# Indexes
#
#  index_user_profiles_on_user_id  (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class UserProfile < ApplicationRecord
  BUDGET_OPTIONS = %w[free low medium high].freeze

  belongs_to :user, optional: true

  validates :name, presence: true, if: :name_step?
  validates :location, presence: true, if: :location_step?
  validates :budget, inclusion: { in: BUDGET_OPTIONS }, if: :budget_step?, allow_nil: true
  validates :ip_address, presence: true, uniqueness: true, if: :temporary?
  
  serialize :interests, type: Array, coder: YAML
  serialize :dietary_preferences, type: Array, coder: YAML
  serialize :allergies, type: Array, coder: YAML

  enum :time_preference, {
    anytime: 0,
    morning: 1,    # 6am-11am
    afternoon: 2,  # 11am-5pm
    evening: 3     # 5pm-11pm
  }

  enum :duration_preference, {
    flexible: 0,
    quick: 1,      # 1-2 hours
    medium: 2,     # 2-4 hours
    extended: 3    # 4+ hours
  }
  
  # Optional specific datetime
  attribute :preferred_date, :datetime

  # Association that works for both temporary (IP-based) and authenticated (user-based) profiles
  has_many :saved_dates, ->(profile) {
    if profile.temporary?
      where(ip_address: profile.ip_address, user_id: nil)
    elsif profile.user_id
      where(user_id: profile.user_id)
    else
      none
    end
  }, class_name: 'SavedDate', foreign_key: :user_id, primary_key: :user_id

  has_many :date_suggestions, through: :saved_dates
  
  scope :temporary, -> { where(temporary: true) }
  scope :for_ip, ->(ip) { where(ip_address: ip) }
  
  def self.find_or_create_temporary(ip_address)
    find_or_create_by!(ip_address: ip_address, temporary: true)
  end

  STEPS = %w[name location dietary_preferences allergies budget].freeze

  def next_step(current_step)
    current_index = STEPS.index(current_step)
    return nil unless current_index
    STEPS[current_index + 1]
  end

  def previous_step(current_step)
    current_index = STEPS.index(current_step)
    return nil if current_index.nil? || current_index.zero?
    STEPS[current_index - 1]
  end

  def filled_out?
    name.present? && location.present?
  end

  private

  def name_step?
    changed.include?('name')
  end

  def location_step?
    changed.include?('location')
  end

  def budget_step?
    changed.include?('budget')
  end
end
