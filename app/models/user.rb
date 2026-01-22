# == Schema Information
#
# Table name: users
#
#  id                 :bigint           not null, primary key
#  email              :string           not null
#  encrypted_password :string
#  password_digest    :string
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#
class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  has_one :user_profile, dependent: :destroy
  
  # Delegate common profile attributes for cleaner code
  delegate :name, :location, :filled_out?, to: :user_profile, prefix: false, allow_nil: true
  
  # Check if user has completed their profile
  def profile_complete?
    user_profile&.filled_out? || false
  end
  
  # Ensure temporary profiles are converted when user signs up
  def convert_temporary_profile(ip_address)
    return unless ip_address.present?
    
    temp_profile = UserProfile.find_by(temporary: true, ip_address: ip_address)
    return unless temp_profile
    
    # Transfer temporary profile to authenticated user
    temp_profile.update(user: self, temporary: false, ip_address: nil)
  end
end
