require 'rails_helper'

feature 'managing email address' do
  context 'show one email address if only one is configured' do
    scenario 'shows one email address for a user with only one' do
      user = create(:user, :signed_up, :with_multiple_emails)
      sign_in_and_2fa_user(user)

      expect(page).to have_content(user.email_addresses.first.email)
    end

    scenario 'shows all email address for a user with multiple emails' do
      user = create(:user, :signed_up, :with_multiple_emails)
      email1, email2 = user.reload.email_addresses.map(&:email)
      sign_in_and_2fa_user(user)

      expect(page).to have_content(email1)
      expect(page).to have_content(email2)
    end
  end

  context 'allows management of email address' do
    before do
      allow(FeatureManagement).to receive(:email_addition_enabled?).and_return(false)
    end

    it 'if adding emails is not enabled' do
      user = create(:user, :signed_up)
      sign_in_and_2fa_user(user)

      expect(page).to have_content("#{user.email_addresses.first.email}\nManage")
    end
  end

  context 'does not allow management of email address' do
    before do
      allow(FeatureManagement).to receive(:email_addition_enabled?).and_return(true)
    end

    it 'if adding emails is enabled' do
      user = create(:user, :signed_up)
      sign_in_and_2fa_user(user)

      expect(page).to have_content("#{user.email_addresses.first.email}\nPassword")
    end
  end
end
