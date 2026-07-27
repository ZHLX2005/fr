/// 公历周岁计算（已过生日才算 N 岁）
class AgeCalculator {
  static int calculate(DateTime birthday, DateTime today) {
    var age = today.year - birthday.year;
    final birthdayThisYear = DateTime(today.year, birthday.month, birthday.day);
    if (today.isBefore(birthdayThisYear)) age -= 1;
    return age;
  }
}