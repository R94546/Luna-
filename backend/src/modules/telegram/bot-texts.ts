/**
 * Тексты бота — только на узбекском.
 *
 * Рабочие цеха читают по-узбекски, и выбор языка в боте им предлагать
 * незачем: лишний шаг на каждом запуске ради нулевой пользы. Язык
 * администратора (приложение) выбирается отдельно и на бота не влияет.
 *
 * Формат чисел: разряды разделены неразрывным пробелом — «288 000 so'm»
 * читается с телефона заметно лучше, чем «288000».
 */

export function money(value: { toString(): string }): string {
  const [whole] = value.toString().split('.');
  return whole.replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
}

export const texts = {
  // Привязка
  linkSuccess: (name: string) =>
    `✅ Salom, ${name}!\n\nHisobingiz ulandi. Endi bajargan ishingizni shu yerda qayd etishingiz mumkin.`,
  linkInvalid: "❌ Kod noto'g'ri yoki muddati tugagan.\n\nUstangizdan yangi kod so'rang.",
  linkAlreadyUsed: '❌ Bu kod allaqachon ishlatilgan.',
  linkCodeTaken: "❌ Bu Telegram hisobi boshqa xodimga biriktirilgan.",

  // Неизвестный пользователь — намеренно не раскрывает ничего о системе
  unknownUser:
    "Sizning hisobingiz tizimga ulanmagan.\n\nUstangizga murojaat qiling — u sizga ulanish kodini beradi.",

  // Главное меню
  menu: (name: string) => `Salom, ${name}! 👋\n\nNima qilamiz?`,
  btnReport: '🔨 Ish qaydi',
  btnToday: '📅 Bugun',
  btnMonth: '📊 Bu oy',
  btnCancel: '❌ Bekor qilish',
  btnBack: '⬅️ Orqaga',
  btnMore: '📋 Barcha modellar',

  // Мастер отчёта
  askProduct: 'Qaysi modelni tayyorladingiz?',
  askOperation: 'Qaysi amalni bajardingiz?',
  askQuantity: (product: string, operation: string) =>
    `${product} — ${operation}\n\nNecha juft tayyorladingiz?\n\nRaqamni yozing:`,
  quantityInvalid: "Iltimos, faqat raqam yozing. Masalan: 24",
  quantityTooLarge: "Juda katta son. Agar bu haqiqat bo'lsa, ustangizga ayting.",

  reportSaved: (params: {
    product: string;
    operation: string;
    quantity: number;
    rate: string;
    amount: string;
    needsApproval: boolean;
  }) =>
    `✅ Qayd etildi\n\n` +
    `Model: ${params.product}\n` +
    `Amal: ${params.operation}\n` +
    `Miqdor: ${params.quantity} juft\n` +
    `Narx: ${params.rate} so'm\n` +
    `Jami: ${params.amount} so'm` +
    (params.needsApproval ? '\n\n⏳ Usta tasdiqlashini kutmoqda.' : ''),

  btnUndo: '↩️ Bekor qilish',
  undoDone: "↩️ Yozuv o'chirildi.",
  undoTooLate: "Bu yozuvni endi o'chirib bo'lmaydi. Ustangizga murojaat qiling.",

  // Сводки
  todayEmpty: 'Bugun hali hech narsa qayd etilmagan.',
  todayTitle: (quantity: number, amount: string) =>
    `📅 Bugun\n\nJami: ${quantity} juft — ${amount} so'm`,
  monthTitle: (quantity: number, amount: string) =>
    `📊 Bu oy\n\nJami: ${quantity} juft — ${amount} so'm`,
  monthEmpty: 'Bu oyda hali yozuvlar yoq.',
  byProductLine: (name: string, quantity: number, amount: string) =>
    `  • ${name}: ${quantity} juft — ${amount} so'm`,

  // Ошибки
  noProducts: "Hozircha modellar qo'shilmagan. Ustangizga ayting.",
  noOperations: "Hozircha amallar qo'shilmagan. Ustangizga ayting.",
  noRate: (operation: string) =>
    `«${operation}» amali uchun narx belgilanmagan.\n\nUstangizga ayting — u narxni kiritadi.`,
  genericError: "Xatolik yuz berdi. Birozdan so'ng qayta urinib ko'ring.",
  cancelled: 'Bekor qilindi.',

  help:
    'Luna — ish qaydi boti\n\n' +
    'Buyruqlar:\n' +
    '/report — bajargan ishni qayd etish\n' +
    '/today — bugungi natija\n' +
    '/month — shu oylik natija\n' +
    '/help — shu yordam\n\n' +
    "Tez yozish: model nomi va sonini yozing, masalan «Sport-12 24»",
};
