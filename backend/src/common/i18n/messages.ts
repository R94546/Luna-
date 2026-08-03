/**
 * Тексты, которые видит пользователь.
 *
 * Основной язык — узбекский (на нём работает цех), русский — запасной.
 * Своя реализация вместо nestjs-i18n: словарь плоский, подстановка одна,
 * а библиотека тянет загрузку файлов, кэш и middleware ради того же результата.
 *
 * Правило: сообщение об ошибке ВСЕГДА берётся отсюда по ключу. Литералов
 * в сервисах быть не должно — иначе половина текстов останется без перевода.
 */

export type Lang = 'uz' | 'ru';

export const DEFAULT_LANG: Lang = 'uz';
export const SUPPORTED_LANGS: Lang[] = ['uz', 'ru'];

type Dict = Record<string, string>;

const uz: Dict = {
  // Общие
  'error.not_found': '{entity} topilmadi',
  'error.internal': 'Serverda xatolik yuz berdi',
  'error.validation': "Maydonlar to'g'ri to'ldirilganini tekshiring",
  'error.forbidden_role': 'Bu amal uchun huquqingiz yetarli emas',
  'error.unauthorized': 'Avtorizatsiya talab qilinadi',
  'error.duplicate': '«{field}» maydonida bunday qiymatli yozuv allaqachon mavjud',
  'error.duplicate_generic': 'Bunday yozuv allaqachon mavjud',
  'error.related_missing': "Bog'liq yozuv mavjud emas",
  'error.database': "Ma'lumotlar bazasi xatosi",
  'error.too_many_requests': "Juda ko'p so'rov. Biroz kuting",

  // Авторизация
  'error.invalid_credentials': "Telefon raqami yoki parol noto'g'ri",
  'error.phone_taken': "Bu raqam allaqachon ro'yxatdan o'tgan",
  'error.token_expired': 'Sessiya muddati tugadi',
  'error.invalid_refresh_token': 'Sessiya yaroqsiz',
  'error.token_reused': 'Xavfsizlik sababli sessiya tugatildi',
  'error.refresh_token_expired': 'Sessiya muddati tugadi, qaytadan kiring',
  'error.user_inactive': "Hisob o'chirilgan",
  'error.no_company': "Foydalanuvchi korxonaga biriktirilmagan",
  'error.wrong_password': "Joriy parol noto'g'ri kiritilgan",
  'error.subscription_expired': 'Obuna muddati tugadi',

  // Валидация форм
  'validation.company_name': 'Sex nomini kiriting',
  'validation.full_name': 'Ismingizni kiriting',
  'validation.phone_format': "Raqamni +998 XX XXX XX XX ko'rinishida kiriting",
  'validation.password_min': "Parol kamida 6 ta belgidan iborat bo'lishi kerak",
  'validation.password_max': 'Parol juda uzun',
  'validation.password_required': 'Parolni kiriting',
  'validation.required': 'Majburiy maydon',
  'validation.positive': "Qiymat noldan katta bo'lishi kerak",
  'validation.date_format': 'Sana YYYY-MM-DD koʻrinishida boʻlishi kerak',
  'validation.period_order': 'Davr oxiri boshidan oldin boʻlishi mumkin emas',
  'validation.nothing_to_update': "O'zgartirish uchun hech narsa yuborilmadi",
  'validation.category_not_manual':
    "Bu turdagi harakat qo'lda kiritilmaydi — o'z bo'limidan foydalaning",
  'validation.color_format': 'Rang #RRGGBB koʻrinishida boʻlishi kerak',

  // Склад и товары
  // Без кавычек вокруг {productName}: названия моделей часто содержат
  // собственные кавычки («Sport-12»), и обёртка их задваивает.
  'error.insufficient_stock': 'Omborda {productName} modelidan atigi {available} juft bor',
  'error.product_has_history': "Bu modelda harakatlar tarixi bor — uni arxivga o'tkazing",

  // Выработка и зарплата
  'error.work_log_not_pending': 'Faqat tasdiqlanmagan yozuvni tahrirlash mumkin',
  'error.work_log_in_payroll': "Bu yozuv ish haqi davriga kiritilgan — o'zgartirib bo'lmaydi",
  'error.period_already_closed': 'Ish haqi davri allaqachon yopilgan',
  'error.period_overlap': 'Bu sanalar {from} — {to} davri bilan kesishadi',
  'error.idempotency_key_reused':
    "Bu kalit boshqa ma'lumot bilan ishlatilgan — yangi urinish uchun yangi kalit kerak",
  'error.idempotency_in_progress': "Avvalgi so'rov hali bajarilmoqda, biroz kuting",
  'error.rate_not_found': "«{operation}» amali uchun narx belgilanmagan",

  // Заказы
  'error.invalid_status_transition': "Buyurtmani «{from}» holatidan «{to}» holatiga o'tkazib bo'lmaydi",

  // Telegram
  'error.telegram_already_linked': 'Bu Telegram hisobi boshqa xodimga biriktirilgan',
  'error.link_code_invalid': "Kod noto'g'ri yoki muddati o'tgan",
};

const ru: Dict = {
  // Общие
  'error.not_found': '{entity} не найден',
  'error.internal': 'Внутренняя ошибка сервера',
  'error.validation': 'Проверьте правильность заполнения полей',
  'error.forbidden_role': 'Недостаточно прав для этой операции',
  'error.unauthorized': 'Требуется авторизация',
  'error.duplicate': 'Запись с таким значением поля «{field}» уже существует',
  'error.duplicate_generic': 'Такая запись уже существует',
  'error.related_missing': 'Связанная запись не существует',
  'error.database': 'Ошибка базы данных',
  'error.too_many_requests': 'Слишком много запросов. Подождите немного',

  // Авторизация
  'error.invalid_credentials': 'Неверный телефон или пароль',
  'error.phone_taken': 'Этот номер уже зарегистрирован',
  'error.token_expired': 'Срок действия сессии истёк',
  'error.invalid_refresh_token': 'Сессия недействительна',
  'error.token_reused': 'Сессия завершена по соображениям безопасности',
  'error.refresh_token_expired': 'Срок сессии истёк, войдите заново',
  'error.user_inactive': 'Учётная запись отключена',
  'error.no_company': 'Пользователь не привязан к компании',
  'error.wrong_password': 'Текущий пароль указан неверно',
  'error.subscription_expired': 'Срок подписки истёк',

  // Валидация форм
  'validation.company_name': 'Укажите название цеха',
  'validation.full_name': 'Укажите ваше имя',
  'validation.phone_format': 'Введите номер в формате +998 XX XXX XX XX',
  'validation.password_min': 'Пароль должен быть не короче 6 символов',
  'validation.password_max': 'Пароль слишком длинный',
  'validation.password_required': 'Введите пароль',
  'validation.required': 'Обязательное поле',
  'validation.positive': 'Значение должно быть больше нуля',
  'validation.date_format': 'Дата должна быть в формате ГГГГ-ММ-ДД',
  'validation.period_order': 'Конец периода не может быть раньше начала',
  'validation.nothing_to_update': 'Не передано ни одного поля для изменения',
  'validation.category_not_manual':
    'Такое движение вручную не заводится — используйте профильный раздел',
  'validation.color_format': 'Цвет должен быть в формате #RRGGBB',

  // Склад и товары
  'error.insufficient_stock': 'На складе только {available} пар модели {productName}',
  'error.product_has_history': 'У модели есть история движений — переведите её в архив',

  // Выработка и зарплата
  'error.work_log_not_pending': 'Изменить можно только неподтверждённую запись',
  'error.work_log_in_payroll': 'Запись вошла в зарплатный период — изменить нельзя',
  'error.period_already_closed': 'Зарплатный период уже закрыт',
  'error.period_overlap': 'Эти даты пересекаются с периодом {from} — {to}',
  'error.idempotency_key_reused':
    'Этот ключ уже использован с другими данными — для новой попытки нужен новый ключ',
  'error.idempotency_in_progress': 'Предыдущий запрос ещё выполняется, подождите немного',
  'error.rate_not_found': 'Для операции «{operation}» не задана расценка',

  // Заказы
  'error.invalid_status_transition': 'Нельзя перевести заказ из статуса «{from}» в «{to}»',

  // Telegram
  'error.telegram_already_linked': 'Этот Telegram-аккаунт привязан к другому сотруднику',
  'error.link_code_invalid': 'Код неверный или просрочен',
};

/**
 * Экспортируется ради проверки состава.
 *
 * Через `t()` пропажу перевода не поймать: она откатывается на язык по
 * умолчанию, и русский ключ, которого нет, вернёт узбекский текст —
 * работающий, но не переведённый. Сверять надо сами словари.
 */
export const dictionaries: Record<Lang, Dict> = { uz, ru };

/**
 * Переводит ключ, подставляя параметры вида {name}.
 * Отсутствующий ключ возвращается как есть — это заметно в ответе API
 * и сразу видно в тестах, в отличие от пустой строки.
 */
export function t(lang: Lang, key: string, params?: Record<string, unknown>): string {
  const template = dictionaries[lang]?.[key] ?? dictionaries[DEFAULT_LANG][key] ?? key;

  if (!params) return template;

  return template.replace(/\{(\w+)\}/g, (match, name: string) =>
    name in params ? String(params[name]) : match,
  );
}

/**
 * Разбирает заголовок Accept-Language.
 * Флаттер шлёт простое `uz` или `ru`, браузер — `ru-RU,ru;q=0.9`,
 * поэтому берём первые две буквы первого языка.
 */
export function parseLang(header?: string): Lang {
  if (!header) return DEFAULT_LANG;

  const code = header.split(',')[0]?.trim().slice(0, 2).toLowerCase();

  return SUPPORTED_LANGS.includes(code as Lang) ? (code as Lang) : DEFAULT_LANG;
}
