module TwoFactorAuthentication
  class OtpVerificationController < ApplicationController
    include TwoFactorAuthenticatable

    before_action :confirm_multiple_factors_enabled
    before_action :confirm_voice_capability, only: [:show]

    def show
      analytics.track_event(Analytics::MULTI_FACTOR_AUTH_ENTER_OTP_VISIT, analytics_properties)

      @presenter = presenter_for_two_factor_authentication_method
    end

    def create
      result = OtpVerificationForm.new(current_user, sanitized_otp_code).submit
      post_analytics(result)
      if result.success?
        handle_valid_otp
      else
        handle_invalid_otp
      end
    end

    private

    def confirm_multiple_factors_enabled
      return if confirmation_context? || phone_enabled?

      if MfaPolicy.new(current_user, user_session[:signing_up]).sufficient_factors_enabled? &&
         !phone_enabled? && user_signed_in?
        return redirect_to user_two_factor_authentication_url
      end

      redirect_to phone_setup_url
    end

    def phone_enabled?
      TwoFactorAuthentication::PhonePolicy.new(current_user).enabled?
    end

    def confirm_voice_capability
      return if two_factor_authentication_method == 'sms'

      capabilities = PhoneNumberCapabilities.new(phone)

      return unless capabilities.sms_only?

      flash[:error] = t(
        'two_factor_authentication.otp_delivery_preference.phone_unsupported',
        location: capabilities.unsupported_location,
      )
      redirect_to login_two_factor_url(otp_delivery_preference: 'sms', reauthn: reauthn?)
    end

    def phone
      MfaContext.new(current_user).phone_configuration(user_session[:phone_id])&.phone ||
        user_session[:unconfirmed_phone]
    end

    def sanitized_otp_code
      form_params[:code].strip
    end

    def form_params
      params.permit(:code)
    end

    def post_analytics(result)
      properties = result.to_h.merge(analytics_properties)
      if context == 'confirmation'
        analytics.track_event(Analytics::MULTI_FACTOR_AUTH_SETUP, properties)
      end

      analytics.track_mfa_submit_event(properties, ga_cookie_client_id)
    end

    def analytics_properties
      {
        context: context,
        multi_factor_auth_method: params[:otp_delivery_preference],
        confirmation_for_phone_change: confirmation_for_phone_change?,
      }
    end
  end
end
