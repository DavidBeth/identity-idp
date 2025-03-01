require 'rails_helper'

feature 'Changing authentication factor' do
  describe 'requires re-authenticating' do
    let(:user) { sign_up_and_2fa_loa1_user }

    before do
      user # Sign up the user
      reauthn_date = (Figaro.env.reauthn_window.to_i + 1).seconds.from_now
      Timecop.travel reauthn_date
    end

    after do
      Timecop.return
    end

    scenario 'editing password' do
      visit manage_password_path

      expect(page).to have_content t('help_text.change_factor', factor: 'password')

      complete_2fa_confirmation

      expect(current_path).to eq manage_password_path
    end

    scenario 'editing phone number' do
      allow(Figaro.env).to receive(:otp_delivery_blocklist_maxretry).and_return('4')

      mailer = instance_double(ActionMailer::MessageDelivery, deliver_later: true)
      user.email_addresses.each do |email_address|
        allow(UserMailer).to receive(:phone_added).
          with(email_address, hash_including(:disavowal_token)).
          and_return(mailer)
      end

      @previous_phone_confirmed_at =
        MfaContext.new(user).phone_configurations.reload.first.confirmed_at
      new_phone = '+1 703-555-0100'

      visit manage_phone_path(id: user.phone_configurations.first.id)

      expect(page).to have_content t('help_text.change_factor', factor: 'phone')

      complete_2fa_confirmation

      update_phone_number
      expect(page).to have_link t('links.cancel'), href: account_path
      expect(page).to have_link t('forms.two_factor.try_again'), href: manage_phone_path
      expect(page).not_to have_content(
        t('two_factor_authentication.personal_key_fallback.text_html'),
      )

      enter_incorrect_otp_code

      expect(page).to have_content t('two_factor_authentication.invalid_otp')
      expect(MfaContext.new(user).phone_configurations.reload.first.phone).to_not eq new_phone
      expect(page).to have_link t('forms.two_factor.try_again'), href: manage_phone_path

      submit_correct_otp

      expect(current_path).to eq account_path
      user.email_addresses.each do |email_address|
        expect(UserMailer).to have_received(:phone_added).
          with(email_address, hash_including(:disavowal_token))
      end
      expect(mailer).to have_received(:deliver_later)
      expect(page).to have_content new_phone
      expect(
        MfaContext.new(user).phone_configurations.reload.first.confirmed_at,
      ).to_not eq(@previous_phone_confirmed_at)

      visit login_two_factor_path(otp_delivery_preference: 'sms')
      expect(current_path).to eq account_path
    end

    scenario 'editing phone number with no voice otp support only allows sms delivery' do
      user.update(otp_delivery_preference: 'voice')
      MfaContext.new(user).phone_configurations.first.update(delivery_preference: 'voice')
      unsupported_phone = '242-327-0143'

      visit manage_phone_path
      complete_2fa_confirmation

      Twilio::FakeCall.calls = []

      select 'Bahamas', from: 'user_phone_form_international_code'
      fill_in 'user_phone_form_phone', with: unsupported_phone
      click_button t('forms.buttons.submit.confirm_change')

      expect(current_path).to eq manage_phone_path
      expect(page).to have_content t(
        'two_factor_authentication.otp_delivery_preference.phone_unsupported',
        location: 'Bahamas',
      )
      expect(Twilio::FakeCall.calls).to eq([])
      expect(page).to_not have_content(t('links.two_factor_authentication.resend_code.phone'))
    end

    scenario 'waiting too long to change phone number' do
      allow(SmsOtpSenderJob).to receive(:perform_later)

      user = sign_in_and_2fa_user
      old_phone = MfaContext.new(user).phone_configurations.first.phone
      visit manage_phone_path
      update_phone_number

      Timecop.travel(Figaro.env.reauthn_window.to_i + 1) do
        click_link t('forms.two_factor.try_again'), href: manage_phone_path
        complete_2fa_confirmation_without_entering_otp

        expect(SmsOtpSenderJob).to have_received(:perform_later).
          with(
            code: user.reload.direct_otp,
            phone: old_phone,
            otp_created_at: user.reload.direct_otp_sent_at.to_s,
            message: 'jobs.sms_otp_sender_job.login_message',
            locale: nil,
          )

        expect(page).to have_content UserDecorator.new(user).masked_two_factor_phone_number
        expect(page).not_to have_link t('forms.two_factor.try_again')
      end
    end

    context 'resending OTP code to old phone' do
      it 'resends OTP and prompts user to enter their code' do
        allow(SmsOtpSenderJob).to receive(:perform_later)

        user = sign_in_and_2fa_user
        old_phone = MfaContext.new(user).phone_configurations.first.phone

        Timecop.travel(Figaro.env.reauthn_window.to_i + 1) do
          visit manage_phone_path
          complete_2fa_confirmation_without_entering_otp
          click_link t('links.two_factor_authentication.get_another_code')

          expect(SmsOtpSenderJob).to have_received(:perform_later).
            with(
              code: user.reload.direct_otp,
              phone: old_phone,
              otp_created_at: user.reload.direct_otp_sent_at.to_s,
              message: 'jobs.sms_otp_sender_job.login_message',
              locale: nil,
            )

          expect(current_path).
            to eq login_two_factor_path(otp_delivery_preference: 'sms')
        end
      end
    end

    scenario 'deleting account' do
      visit account_delete_path

      expect(page).to have_content t('help_text.no_factor.delete_account')
      complete_2fa_confirmation

      expect(current_path).to eq account_delete_path
    end
  end

  context 'with SMS and number that Verify does not think is valid' do
    it 'rescues the VerifyError' do
      allow(Twilio::FakeVerifyAdapter).to receive(:post).
        and_return(Twilio::FakeVerifyAdapter::ErrorResponse.new)

      user = create(:user, :signed_up, with: { phone: '+17035551212' })
      visit new_user_session_path
      sign_in_live_with_2fa(user)
      visit manage_phone_path
      select 'Morocco', from: 'user_phone_form_international_code'
      fill_in 'user_phone_form_phone', with: '+212 661-289325'
      click_button t('forms.buttons.submit.confirm_change')

      expect(current_path).to eq manage_phone_path
      expect(page).to have_content t('errors.messages.invalid_phone_number')
    end
  end

  def complete_2fa_confirmation
    complete_2fa_confirmation_without_entering_otp
    fill_in_code_with_last_phone_otp
    click_submit_default
  end

  def complete_2fa_confirmation_without_entering_otp
    expect(current_path).to eq user_password_confirm_path

    fill_in 'Password', with: Features::SessionHelper::VALID_PASSWORD
    click_button t('forms.buttons.continue')

    expect(current_path).to eq login_two_factor_path(
      otp_delivery_preference: user.otp_delivery_preference,
    )
  end

  def update_phone_number(phone = '703-555-0100')
    fill_in 'user_phone_form[phone]', with: phone
    click_button t('forms.buttons.submit.confirm_change')
  end

  def enter_incorrect_otp_code
    fill_in 'code', with: '12345'
    click_submit_default
  end

  def submit_current_password_and_totp
    fill_in 'Password', with: Features::SessionHelper::VALID_PASSWORD
    click_button t('forms.buttons.continue')

    expect(current_path).to eq login_two_factor_authenticator_path

    fill_in 'code', with: generate_totp_code(@secret)
    click_submit_default
  end

  def submit_correct_otp
    fill_in_code_with_last_phone_otp
    click_submit_default
  end

  describe 'attempting to bypass current password entry' do
    it 'does not allow bypassing this step' do
      sign_in_and_2fa_user
      Timecop.travel(Figaro.env.reauthn_window.to_i + 1) do
        visit manage_password_path
        expect(current_path).to eq user_password_confirm_path

        visit login_two_factor_path(otp_delivery_preference: 'sms')

        expect(current_path).to eq user_password_confirm_path
      end
    end
  end
end
