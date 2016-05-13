# name: discourse-cakeday
# about: Show a birthday cake beside the user's name on their birthday or on the date they joined Discourse.
# version: 0.0.2
# authors: Alan Tan
# url: https://github.com/tgxworld/discourse-cakeday

enabled_site_setting :cakeday_enabled

PLUGIN_NAME = "discourse-cakeday"

register_asset 'stylesheets/cakeday.scss'

after_initialize do
  module ::DiscourseCakeday
    class Engine < ::Rails::Engine
      engine_name PLUGIN_NAME
      isolate_namespace DiscourseCakeday
    end
  end

  require_dependency "application_controller"

  ::DiscourseCakeday::Engine.routes.draw do
    get "birthdays" => "users#birthdays"
    get "anniversaries" => "users#anniversaries"
  end

  Discourse::Application.routes.append do
    mount ::DiscourseCakeday::Engine, at: "/cakeday"
  end

  require_dependency 'user'

  class ::User
    scope :birthday_month, ->(month) {
      joins(:_custom_fields)
      .where("user_custom_fields.name = 'date_of_birth'")
      .where("(user_custom_fields.value = '') IS NOT TRUE")
      .where("EXTRACT(MONTH FROM user_custom_fields.value::date) = ?", month)
      .order("EXTRACT(MONTH FROM user_custom_fields.value::date) ASC")
      .order("EXTRACT(DAY FROM user_custom_fields.value::date) ASC")
    }

    scope :anniversary_month, ->(month) {
      where("EXTRACT(MONTH FROM users.created_at::date) = ?", month)
      .order("EXTRACT(MONTH FROM users.created_at::date) ASC, users.created_at ASC")
    }
  end

  module ::DiscourseCakeday
    class UsersController < ::ApplicationController
      PAGE_SIZE = 48

      before_action :setup_params

      def anniversaries
        users = User.anniversary_month(@month)
        total_rows_count = users.count
        anniversary_month_users = User.anniversary_month(@current_month)
        anniversary_users = anniversary_month_users.where(created_at: @today)
        upcoming_anniversay_users = anniversary_month_users.where("users.created_at BETWEEN ? AND ?", @tomorrow, @week_from_now)
        users = users.limit(PAGE_SIZE).offset(PAGE_SIZE * @page)

        render_json_dump(
          anniversaries: serialize_data(users, AnniversaryUserSerializer),
          extras: {
            today: serialize_data(anniversary_users, AnniversaryUserSerializer),
            upcoming: serialize_data(upcoming_anniversay_users, AnniversaryUserSerializer)
          },
          total_rows_anniversaries: total_rows_count,
          load_more_anniversaries: anniversaries_path({ page: @page + 1, month: params[:month] })
        )
      end

      def birthdays
        users = User.birthday_month(@month)
        total_rows_count = users.count
        birthday_month_users = User.birthday_month(@current_month)

        birthday_users = select_fields(
          birthday_month_users
            .where("EXTRACT(MONTH FROM user_custom_fields.value::date) = ?", @today.month)
            .where("EXTRACT(DAY FROM user_custom_fields.value::date) = ?", @today.day)
        )

        upcoming_birthday_users = select_fields(
          birthday_month_users
            .where("EXTRACT(MONTH FROM user_custom_fields.value::date) IN (?)", [@tomorrow.month.to_s, @week_from_now.month.to_s])
            .where("EXTRACT(DAY FROM user_custom_fields.value::date) IN (?)", (@tomorrow..@week_from_now).map(&:day))
        )

        users = select_fields(users.limit(PAGE_SIZE).offset(PAGE_SIZE * @page))

        render_json_dump(
          birthdays: serialize_data(users, BirthdayUserSerializer),
          extras: {
            today: serialize_data(birthday_users, BirthdayUserSerializer),
            upcoming: serialize_data(upcoming_birthday_users, BirthdayUserSerializer)
          },
          total_rows_birthdays: total_rows_count,
          load_more_birthdays: birthdays_path({ page: @page + 1, month: params[:month] })
        )
      end

      private

      def setup_params
        @page = params[:page].to_i
        @month = Date::MONTHNAMES.index(params[:month])
        @current_month = Date.today.month
        @today = Date.today
        @tomorrow = Date.tomorrow
        @week_from_now = 1.week.from_now
      end

      def select_fields(users)
        users.select(:id, :username, :name, :title, :uploaded_avatar_id)
          .select("user_custom_fields.value AS date_of_birth")
      end
    end
  end

  require_dependency 'user_name_serializer'
  class BirthdayUserSerializer < UserNameSerializer
    attributes :cakeday_date

    def cakeday_date
      object.date_of_birth.strftime("%m/%d")
    end
  end

  class AnniversaryUserSerializer < UserNameSerializer
    attributes :cakeday_date

    def cakeday_date
      object.created_at.strftime("%Y/%m/%d")
    end
  end

  require_dependency 'post_serializer'
  require_dependency 'user_serializer'

  public_user_custom_fields_setting = SiteSetting.public_user_custom_fields

  if public_user_custom_fields_setting.empty?
    SiteSetting.set("public_user_custom_fields", "date_of_birth")
  elsif public_user_custom_fields_setting !~ /date_of_birth/
    SiteSetting.set(
      "public_user_custom_fields",
      [SiteSetting.public_user_custom_fields, "date_of_birth"].join("|")
    )
  end

  class ::UserSerializer
    alias_method :_custom_fields, :custom_fields
    def custom_fields
      if !object.custom_fields["date_of_birth"]
        object.custom_fields["date_of_birth"] = ""
        object.save
      end
      _custom_fields
    end
  end

  class ::PostSerializer
    attributes :user_created_at

    def user_created_at
      object.user.try(:created_at)
    end
  end
end
