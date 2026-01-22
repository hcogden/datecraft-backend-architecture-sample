# == Schema Information
#
# Table name: date_suggestions
#
#  id                     :bigint           not null, primary key
#  budget                 :integer          default("low")
#  category               :integer          default("dining")
#  description            :text
#  duration               :float
#  location               :string
#  recommended_start_time :string
#  sequence               :integer
#  title                  :string           not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  parent_suggestion_id   :bigint
#
# Indexes
#
#  index_date_suggestions_on_parent_suggestion_id  (parent_suggestion_id)
#
# Foreign Keys
#
#  fk_rails_...  (parent_suggestion_id => date_suggestions.id)
#
class DateSuggestion < ApplicationRecord
  validates :title, :description, :category, :budget, presence: true
  validates :duration, numericality: { greater_than: 0 }, allow_nil: true
  
  has_many :saved_dates
  has_many :planning_sessions
  
  enum :budget, { 
    free: 0,
    low: 1, 
    medium: 2, 
    high: 3 
  }
  enum :category, { 
    dining: 0, 
    outdoor: 1, 
    entertainment: 2, 
    adventure: 3, 
    relaxation: 4,
    cultural: 5
  }
  
  belongs_to :parent_suggestion, class_name: 'DateSuggestion', optional: true, inverse_of: :child_suggestions
  has_many :child_suggestions, class_name: 'DateSuggestion', foreign_key: 'parent_suggestion_id', 
    dependent: :destroy, inverse_of: :parent_suggestion
  
  scope :parent_suggestions, -> { where(parent_suggestion_id: nil) }
  scope :ordered_sequence, -> { order(sequence: :asc) }
  scope :by_category, ->(category) { where(category: category) }
  scope :by_budget, ->(budget) { where(budget: budget) }
  scope :recent, -> { order(created_at: :desc) }
  
  default_scope -> { order(created_at: :desc) }
  
  def all_suggestions
    # Navigate to parent if this is a child, then get all in sequence
    root = parent_suggestion || self
    return [root] if root.child_suggestions.empty?
    [root] + root.child_suggestions.ordered_sequence
  end
  
  def total_duration
    # Use SQL aggregation for better performance
    root = parent_suggestion || self
    return duration || 0 if root.child_suggestions.empty?
    
    root.child_suggestions.unscope(:order).sum(:duration).to_f + (root.duration || 0)
  end
  
  def google_maps_url
    return nil unless location
    "https://www.google.com/maps/search/?api=1&query=#{URI.encode_www_form_component(location)}"
  end
end
