# == Schema Information
#
# Table name: devices
#
#  id               :integer          not null      # Primary key
#  device_token     :string(255)
#  device_type      :string(255)                    # Mobile device type (ios, android)
#  user_id          :integer                        # Foreign key to users
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#

class Device < ActiveRecord::Base

  # Constants
  #----------------------------------------------------------------------
  DEVICE_TYPE = %w[ios android]
  REMOTE_NOTE_TYPE = {new_message: "N", read_sent_message: "R"}
  TEST_ALERT = "Test! This is a test notification from SimpleChat!"

  # Associations
  #----------------------------------------------------------------------
  belongs_to :user

  # Validations
  #----------------------------------------------------------------------
  validates_uniqueness_of :device_token, scope: :user_id

  # Scopes
  #----------------------------------------------------------------------
  scope :ios_devices, -> { where(device_type: Device::DEVICE_TYPE[0]) }
  scope :android_devices, -> { where(device_type: Device::DEVICE_TYPE[1]) }

  # Methods
  #----------------------------------------------------------------------
  class << self

    include ApplicationHelper

    def alert_text_on_new_message(message, locale=nil)
      if message.sender.group?
        I18n.t(
          "alert_texts.new_message.group", locale: locale || app_locale, 
          group_sender_name: message.group_sender.full_name2,
          group_name: message.sender.group_name)
      else
        I18n.t(
          "alert_texts.new_message.user", locale: locale || app_locale, 
          sender_name: message.sender.full_name2)
      end
    end

    def alert_text_on_group_user_add_by_system(invited=nil, inviter=nil, locale=nil)
      if inviter.present?
        if invited.present?
          I18n.t(
            "alert_texts.group_user_add_by_system.with_inviter.with_invited", locale: locale || app_locale, 
            inviter_name: inviter.full_name2, invited_name: invited.full_name2)
        else
          I18n.t("alert_texts.group_user_add_by_system.with_inviter.without_invited", 
            locale: locale || app_locale, inviter_name: inviter.full_name2)
        end
      else
        if invited.present?
          I18n.t("alert_texts.group_user_add_by_system.without_inviter.with_invited", 
            locale: locale || app_locale, invited_name: invited.full_name2)
        else
          I18n.t("alert_texts.group_user_add_by_system.without_inviter.without_invited", 
            locale: locale || app_locale)
        end
      end
    end

    def send_notification(target_user, alert=TEST_ALERT, data=nil, priority=Message::PRIORITY[:normal])
      begin
        if Rails.env.development?
          ios_app      = Rpush::Apns::App.find_by_name("ios_development_app")
          android_app  = Rpush::Gcm::App.find_by_name("android_app")
        else
          ios_app     = Rpush::Client::Redis::App.all.first
          android_app = Rpush::Client::Redis::App.all.second
        end

        target_user.devices.each do |d|
          if d.device_type == "ios"
            n = Rpush::Apns::Notification.new
            n.app = ios_app
            n.device_token = d.device_token
            n.alert = alert if alert.present?
            if data.present?
              n.data = data
              if data[:type].present?
                if data[:type] == REMOTE_NOTE_TYPE[:new_message]
                  n.badge = target_user.received_unread_messages.count
                  # p ">>> >>> X (to iOS): #{n.to_json}"
                  if target_user.notification_app == 0 && priority == Message::PRIORITY[:normal]
                    n.content_available = true
                    n.sound = ""
                  end
                elsif data[:type] == REMOTE_NOTE_TYPE[:read_sent_message]
                  n.content_available = true
                  n.sound = ""
                end
              end
            end
            n.save!

          elsif d.device_type == "android"
            n = Rpush::Gcm::Notification.new
            n.app = android_app
            n.registration_ids = [d.device_token]
            n.notification = {title: alert || "SimpleChat Notification", icon: "ic_launcher.png"}
            n.priority = 'high'
            if data.present?
              n.data = data
              if data[:type].present?
                if data[:type] == REMOTE_NOTE_TYPE[:new_message]
                  data[:badge] = target_user.received_unread_messages.count.try(:to_s)
                  if target_user.notification_app == 0 && priority == Message::PRIORITY[:normal]
                    data[:no_sound] = "Y"
                  end
                  n.data = data
                  p ">>> >>> [Device.send_notification] Android GCM Payload: #{n.to_json}"
                end
              end
            end
            n.save!
          end
        end
        # Rpush.push
        # Rpush.embed
      rescue Exception => e
        p ">>> >>> X1: Exception occurred while sending push notification"
        p e
      end
    end
    # handle_asynchronously :send_notification, priority: 0 #, run_at: Proc.new {1.seconds.from_now}
  end

  def self.test_push(app_name, device_token)
    # app_name: ios_development_app or ios_production_app
    app = Rails.env.development? ? Rpush::Apns::App.find_by_name(app_name) : Rpush::Client::Redis::App.all.first
    
    n = Rpush::Apns::Notification.new
    n.app = app
    n.device_token = device_token
    n.alert = TEST_ALERT
    n.save!
    
    Rpush.push
  end

  def self.test_android_push(device_token)
    n = Rpush::Gcm::Notification.new
    n.app = Rails.env.development? ? Rpush::Gcm::App.find_by_name("android_app") : Rpush::Client::Redis::App.all.second
    n.registration_ids = [device_token]
    n.data = { message: TEST_ALERT }
    n.priority = 'high'        # Optional, can be either 'normal' or 'high'
    n.content_available = true # Optional
    n.notification = { 
      title: TEST_ALERT,
      icon: 'ic_launcher.png'
    }
    n.save!

    Rpush.push
  end
end
