require 'rails_helper'

describe 'two_factor_authentication/otp_verification/show.html.slim' do
  let(:presenter_data) do
    {
      otp_delivery_preference: 'sms',
      phone_number: '***-***-1212',
      code_value: '12777',
      unconfirmed_user: false,
      reenter_phone_number_path: manage_phone_path,
    }
  end

  context 'user has a phone' do
    before do
      allow(view).to receive(:user_session).and_return({})
      allow(view).to receive(:current_user).and_return(User.new)
      allow(view).to receive(:user_fully_authenticated?).and_return(false)
      controller.request.path_parameters[:otp_delivery_preference] =
        presenter_data[:otp_delivery_preference]

      @presenter = TwoFactorAuthCode::PhoneDeliveryPresenter.new(
        data: presenter_data,
        view: view,
      )
      allow(@presenter).to receive(:reauthn).and_return(false)
    end

    context 'common OTP delivery screen behavior' do
      it 'has a localized title' do
        expect(view).to receive(:title).with(t('titles.enter_2fa_code'))

        render
      end

      it 'has a localized heading' do
        render

        expect(rendered).to have_content t('two_factor_authentication.header_text')
      end
    end

    it 'allows the user to cancel and delete their account' do
      render
      expect(rendered).to have_link(t('links.cancel_account_creation'))
    end

    context 'OTP copy' do
      let(:help_text) do
        t('instructions.mfa.sms.number_message',
          number: content_tag(:strong, presenter_data[:phone_number]),
          expiration: Figaro.env.otp_valid_for)
      end

      it 'informs the user that an OTP has been sent to their number via #help_text' do
        render

        expect(rendered).to include help_text
      end

      context 'in other locales' do
        before { I18n.locale = :es }

        it 'translates correctly' do
          render

          expect(rendered).to include help_text
        end
      end
    end

    context 'user signed up' do
      before do
        user = create(:user, :signed_up, personal_key: '1')
        allow(view).to receive(:current_user).and_return(user)
        render
      end

      it_behaves_like 'an otp form'

      it 'provides an option to use a personal key' do
        expect(rendered).to have_link(
          t('two_factor_authentication.login_options_link_text'),
          href: login_two_factor_options_path,
        )
      end
    end

    context 'user is reauthenticating' do
      before do
        user = create(:user, :signed_up, personal_key: '1')
        allow(view).to receive(:current_user).and_return(user)
        allow(@presenter).to receive(:reauthn).and_return(true)
        render
      end

      it 'provides a cancel link to return to profile' do
        expect(rendered).to have_link(
          t('links.cancel'),
          href: account_path,
        )
      end

      it 'renders the reauthn partial' do
        expect(view).to render_template(
          partial: 'two_factor_authentication/totp_verification/_reauthn',
        )
      end
    end

    context 'user is changing phone number' do
      it 'provides a cancel link to return to profile' do
        user = create(:user, :signed_up, personal_key: '1')
        allow(view).to receive(:current_user).and_return(user)
        data = presenter_data.merge(confirmation_for_phone_change: true)
        @presenter = TwoFactorAuthCode::PhoneDeliveryPresenter.new(
          data: data,
          view: view,
        )

        render

        expect(rendered).to have_link(
          t('links.cancel'),
          href: account_path,
        )
      end
    end

    context 'user is unconfirmed' do
      it 'does not provide an option to use a personal key' do
        unconfirmed_data = presenter_data.merge(personal_key_unavailable: true)

        @presenter = TwoFactorAuthCode::PhoneDeliveryPresenter.new(
          data: unconfirmed_data,
          view: view,
        )

        render

        expect(rendered).not_to have_link(
          t('two_factor_authentication.personal_key_fallback.link'),
          href: login_two_factor_personal_key_path,
        )
      end
    end

    context 'when totp is not enabled' do
      it 'does not allow user to sign in using an authenticator app' do
        render

        expect(rendered).not_to have_link(
          t('links.two_factor_authentication.app'), href: login_two_factor_authenticator_path
        )
      end
    end

    context 'when totp is enabled' do
      it 'allows user to sign in using an authenticator app' do
        totp_data = presenter_data.merge(totp_enabled: true)
        @presenter = TwoFactorAuthCode::PhoneDeliveryPresenter.new(
          data: totp_data,
          view: view,
        )

        render

        expect(rendered).to have_link(
          t('two_factor_authentication.login_options_link_text'),
          href: login_two_factor_options_path,
        )
      end
    end

    context 'when @code_value is set' do
      it 'pre-populates the form field' do
        render

        expect(rendered).to have_xpath("//input[@value='12777']")
      end
    end

    context 'when choosing to receive OTP via SMS' do
      let(:otp_delivery_preference) { 'sms' }

      it 'allows user to resend code using the same delivery method' do
        render

        resend_path = otp_send_path(otp_delivery_selection_form: {
                                      otp_delivery_preference: otp_delivery_preference,
                                      resend: true,
                                    })

        expect(rendered).to have_link(
          t('links.two_factor_authentication.get_another_code'),
          href: resend_path,
        )
      end

      it 'has a link to choose a different 2FA method' do
        render

        expect(rendered).to have_link(
          t('two_factor_authentication.login_options_link_text'),
          href: login_two_factor_options_path,
        )
      end
    end

    context 'when choosing to receive OTP via voice' do
      let(:otp_delivery_preference) { 'voice' }

      before do
        controller.request.path_parameters[:otp_delivery_preference] = otp_delivery_preference
        voice_data = presenter_data.merge(otp_delivery_preference: otp_delivery_preference)
        @presenter = TwoFactorAuthCode::PhoneDeliveryPresenter.new(
          data: voice_data,
          view: view,
        )
      end

      it 'allows user to resend code using the same delivery method' do
        render

        resend_path = otp_send_path(
          otp_delivery_selection_form: {
            otp_delivery_preference: otp_delivery_preference,
            resend: true,
          },
        )

        expect(rendered).to have_link(
          t('links.two_factor_authentication.get_another_code'),
          href: resend_path,
        )
      end

      it 'has a fallback link to send confirmation as SMS' do
        render

        expect(rendered).to have_link(
          t('two_factor_authentication.login_options_link_text'),
          href: login_two_factor_options_path,
        )
      end
    end

    context 'when users phone number is unconfirmed' do
      it 'has a link to choose a new phone number' do
        data = presenter_data.merge(unconfirmed_phone: true)

        @presenter = TwoFactorAuthCode::PhoneDeliveryPresenter.new(
          data: data,
          view: view,
        )

        render

        expect(rendered).to have_link(t('forms.two_factor.try_again'), href: manage_phone_path)
      end
    end

    context 'when users phone number is unconfirmed' do
      it 'has a link to choose a new phone number' do
        data = presenter_data.merge(unconfirmed_phone: true)

        @presenter = TwoFactorAuthCode::PhoneDeliveryPresenter.new(
          data: data,
          view: view,
        )

        render

        expect(rendered).to have_link(t('forms.two_factor.try_again'), href: manage_phone_path)
      end
    end
  end
end
