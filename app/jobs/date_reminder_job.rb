# frozen_string_literal: true

class DateReminderJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: :exponentially_longer, attempts: 3
  
  VALID_NOTIFICATION_TYPES = %i[email sms].freeze

  def perform(planning_session_id, notification_type)
    planning_session = PlanningSession.find_by(id: planning_session_id)
    
    unless planning_session
      Rails.logger.warn "DateReminderJob: PlanningSession #{planning_session_id} not found, skipping notification"
      return
    end
    
    unless VALID_NOTIFICATION_TYPES.include?(notification_type)
      Rails.logger.error "DateReminderJob: Invalid notification type '#{notification_type}'"
      return
    end
    
    case notification_type
    when :email
      send_email_reminder(planning_session)
    when :sms
      send_sms_reminder(planning_session)
    end
  end
  
  private
  
  def send_email_reminder(planning_session)
    unless planning_session.email.present?
      Rails.logger.warn "DateReminderJob: No email for PlanningSession #{planning_session.id}, skipping email"
      return
    end
    
    DateReminderMailer.reminder_email(planning_session).deliver_now
    Rails.logger.info "DateReminderJob: Email reminder sent for PlanningSession #{planning_session.id}"
  rescue StandardError => e
    Rails.logger.error "DateReminderJob: Failed to send email for PlanningSession #{planning_session.id}: #{e.message}"
    raise
  end
  
  def send_sms_reminder(planning_session)
    unless planning_session.phone.present?
      Rails.logger.warn "DateReminderJob: No phone for PlanningSession #{planning_session.id}, skipping SMS"
      return
    end
    
    SmsReminderService.send_reminder(planning_session)
    Rails.logger.info "DateReminderJob: SMS reminder sent for PlanningSession #{planning_session.id}"
  rescue StandardError => e
    Rails.logger.error "DateReminderJob: Failed to send SMS for PlanningSession #{planning_session.id}: #{e.message}"
    raise
  end
end
