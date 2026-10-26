workspace "Сервис каршеринга «ГоуКар»" "Учебная модель: та же, что в 01–04-*.puml, но описанная один раз" {

    model {
        client   = person "Клиент" "Водитель: находит, бронирует, открывает по телефону и завершает аренду автомобиля"
        operator = person "Оператор поддержки" "Разбирает инциденты, проверяет места стоянки, штрафы"

        obu     = softwareSystem "Бортовой модуль" "Телематический блок в автомобиле: замки, GPS, пробег, зажигание" "External"
        payment = softwareSystem "Платёжный шлюз" "Эквайринг: списание с банковских карт" "External"
        sms     = softwareSystem "SMS-шлюз" "Доставка одноразовых кодов входа" "External"

        carsharing = softwareSystem "Сервис каршеринга «ГоуКар»" "Брони, поминутная аренда, тарификация, штрафы, зоны завершения" {
            app     = container "Мобильное приложение" "Карта автомобилей, бронь, открытие по телефону, чек" "Kotlin (Android), Swift (iOS)" "Mobile"
            console = container "Панель оператора" "Инциденты, ручная проверка места стоянки, штрафы" "React" "Web"
            api     = container "Backend API" "Брони, аренды, тарификация, штрафы, зоны; REST" "Kotlin / Spring Boot" {
                ctrl    = component "RentalController" "REST-эндпоинты приложения, панели оператора и служебные" "Spring MVC"
                account = component "AccountService" "Вход по SMS-коду, клиенты, способы оплаты" "Kotlin"
                booking = component "BookingService" "Брони: создание, отмена, истечение" "Kotlin"
                rental  = component "RentalService" "Жизненный цикл аренды (автомат), штрафы" "Kotlin"
                tariff  = component "TariffEngine" "Расчёт стоимости по правилу тарификации" "Kotlin"
                fleet   = component "FleetService" "Автомобили, их состояния, зоны завершения" "Kotlin"
                pay     = component "PaymentService" "Списание через способ оплаты клиента" "Kotlin"
                tele    = component "TelematicsClient" "Команды автомобилю с повторами и таймаутами" "gRPC-клиент"
                repo    = component "Repositories" "Доступ к данным, геозапросы" "Spring Data JPA, Hibernate Spatial"
            }
            tgw    = container "Телематический шлюз" "Держит соединения с тысячами бортовых модулей; команды и телеметрия" "Go"
            worker = container "Обработчик событий" "Истечение броней, повтор списаний, заявки на эвакуацию" "Kotlin"
            db     = container "Основная БД" "Клиенты, брони, аренды, штрафы, полигоны зон" "PostgreSQL 16 + PostGIS" "Database"
            bus    = container "Очередь событий" "RentalClosed, EvacuationRequested, DebtRegistered, ManualCheckRequired" "RabbitMQ" "Queue"
        }

        # Уровень 1 — явные связи, чтобы на контексте были свои формулировки
        client     -> carsharing "Ищет, бронирует, открывает и завершает аренду" "HTTPS"
        operator   -> carsharing "Разбирает инциденты и ручные проверки" "HTTPS"
        carsharing -> obu "Команды «открыть» / «закрыть», запрос телеметрии" "MQTT/TLS"
        obu        -> carsharing "Координаты, пробег, зажигание" "MQTT/TLS"
        carsharing -> payment "Списывает стоимость поездок и штрафы" "HTTPS/REST"
        carsharing -> sms "Отправляет коды входа" "HTTPS"

        # Уровень 2
        client   -> app "Пользуется"
        operator -> console "Пользуется" "HTTPS"
        app      -> api "Вызывает" "JSON/HTTPS"
        console  -> api "Вызывает" "JSON/HTTPS"
        api      -> db "Читает и пишет" "JDBC"
        api      -> tgw "Команды автомобилю, запрос телеметрии" "gRPC"
        tgw      -> obu "Команды; принимает телеметрию" "MQTT/TLS"
        api      -> bus "Публикует доменные события" "AMQP"
        bus      -> worker "Доставляет события" "AMQP"
        worker   -> api "Вызывает служебные операции" "JSON/HTTPS"
        api      -> payment "Списывает оплату и штрафы" "HTTPS/REST"
        api      -> sms "Отправляет коды входа" "HTTPS"

        # Уровень 3
        app     -> ctrl "Брони, аренды" "JSON/HTTPS"
        console -> ctrl "Инциденты, проверки" "JSON/HTTPS"
        worker  -> ctrl "Служебные операции" "JSON/HTTPS"
        ctrl    -> account "вход, профиль"
        ctrl    -> booking "брони"
        ctrl    -> rental "аренды"
        booking -> fleet "резервирует автомобиль"
        rental  -> booking "использует бронь"
        rental  -> tele "открыть / закрыть, координаты"
        rental  -> fleet "проверяет зону, меняет состояние авто"
        rental  -> tariff "рассчитывает стоимость"
        rental  -> pay "списывает оплату"
        pay     -> account "способ оплаты клиента"
        account -> repo "использует"
        booking -> repo "использует"
        rental  -> repo "использует"
        fleet   -> repo "использует"
        repo    -> db "Читает и пишет" "JDBC"
        rental  -> bus "Публикует события" "AMQP"
        tele    -> tgw "Команды и телеметрия" "gRPC"
        pay     -> payment "Списание" "HTTPS/REST"
        account -> sms "Коды входа" "HTTPS"
    }

    views {
        properties {
            "c4plantuml.tags" "true"
        }

        systemContext carsharing "Context" "Уровень 1 — System Context" {
            include *
            autolayout tb
        }
        container carsharing "Containers" "Уровень 2 — Containers" {
            include *
            autolayout tb
        }
        component api "Components" "Уровень 3 — Components: Backend API" {
            include *
            autolayout tb
        }
        dynamic carsharing "FinishOutsideZone" "ВИ-05 «Завершить аренду»: вне зоны, клиент завершает со штрафом" {
            client  -> app "Нажимает «Завершить аренду»"
            app     -> api "POST /rentals/{id}/finish"
            api     -> tgw "Запросить координаты и пробег"
            tgw     -> obu "Запрос телеметрии (до 3 попыток)"
            api     -> db "ST_Contains(зона, точка) → вне зоны"
            app     -> api "Клиент подтвердил завершение со штрафом"
            api     -> db "Штраф ЗАВЕРШЕНИЕ_ВНЕ_ЗОНЫ, стоимость, статус ОЖИДАЕТ_ОПЛАТЫ"
            api     -> payment "Списать стоимость + штраф"
            api     -> tgw "Заблокировать двери"
            api     -> bus "EvacuationRequested, RentalClosed"
            bus     -> worker "Доставляет EvacuationRequested"
            worker  -> api "Пометить авто ТРЕБУЕТ_ЭВАКУАЦИИ, задача оператору"
            autolayout tb
        }

        styles {
            element "Person" {
                shape Person
                background #08427b
                color #ffffff
            }
            element "Software System" {
                background #1168bd
                color #ffffff
            }
            element "External" {
                background #999999
                color #ffffff
            }
            element "Container" {
                background #438dd5
                color #ffffff
            }
            element "Component" {
                background #85bbf0
                color #000000
            }
            element "Database" {
                shape Cylinder
            }
            element "Queue" {
                shape Pipe
            }
            element "Mobile" {
                shape MobileDevicePortrait
            }
            element "Web" {
                shape WebBrowser
            }
        }
    }
}
