CREATE SCHEMA IF NOT EXISTS e_ticaret AUTHORIZATION shop_user;
SET search_path TO e_ticaret, public;

-- tek seferlik anonim bir kod bloğu çalıştırır.
-- BEGIN … END → Bloğun gövdesi; burada koşullu bir kontrol yapıyoruz.

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'odeme_turu') THEN
    CREATE TYPE odeme_turu AS ENUM ('KREDI_KARTI','HAVALE','KAPIDA','E_CUZDAN');
  END IF;
END$$;

-- kategoriyi primary key olarak belirledim.

CREATE TABLE IF NOT EXISTS kategori (
  id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ad TEXT NOT NULL UNIQUE
);

-- satıcı id'si primary key olmalı. satıcı adı zorunlu.

CREATE TABLE IF NOT EXISTS satici (
  id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ad TEXT NOT NULL,
  adres TEXT
);

-- zorunlu kimlik alanı / eposta tekiliği / tarih boş bırakılırsa o günün tarihi

CREATE TABLE IF NOT EXISTS musteri (
  id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ad TEXT NOT NULL,
  soyad TEXT NOT NULL,
  email TEXT NOT NULL UNIQUE,
  sehir TEXT,
  kayit_tarihi DATE NOT NULL DEFAULT CURRENT_DATE
);

-- ürün adı zorunlu / fiyatta negatif sayıyı engeller/ ürün kategoriye ve satıcıya bağlı olmak zorunda

CREATE TABLE IF NOT EXISTS urun (
  id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ad TEXT NOT NULL,
  fiyat NUMERIC(12,2) NOT NULL CHECK (fiyat >= 0),
  stok INT NOT NULL CHECK (stok >= 0),
  kategori_id INT NOT NULL REFERENCES kategori(id),
  satici_id INT NOT NULL REFERENCES satici(id),
  aktif BOOLEAN NOT NULL DEFAULT TRUE
);


-- sipariş

CREATE TABLE IF NOT EXISTS siparis (
  id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  musteri_id INT NOT NULL REFERENCES musteri(id),
  tarih TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  toplam_tutar NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (toplam_tutar >= 0),
  odeme_turu odeme_turu NOT NULL DEFAULT 'KREDI_KARTI'
);

-- sipariş silinirse detaylı satır silinecek/ ürünle ilişkisi kuruldu/ her ürün bir kez alınabilir.

CREATE TABLE IF NOT EXISTS siparis_detay (
  id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  siparis_id INT NOT NULL REFERENCES siparis(id) ON DELETE CASCADE,
  urun_id INT NOT NULL REFERENCES urun(id),
  adet INT NOT NULL CHECK (adet > 0),
  fiyat NUMERIC(12,2) NOT NULL CHECK (fiyat >= 0),
  UNIQUE (siparis_id, urun_id)
);


---3. bölüm B kısmı


INSERT INTO e_ticaret.kategori (ad) VALUES
('Elektronik'), ('Moda'), ('Ev & Yaşam'), ('Oyuncak');

INSERT INTO e_ticaret.satici (ad, adres) VALUES
('TechnoStore','İstanbul'),('ModaX','İzmir'),('HomePlus','Ankara');

INSERT INTO e_ticaret.musteri (ad, soyad, email, sehir) VALUES
('Ayşe','Yılmaz','ayse@example.com','İstanbul'),
('Mehmet','Demir','mehmet@example.com','Ankara'),
('Zeynep','Kaya','zeynep@example.com','İzmir');

INSERT INTO e_ticaret.urun (ad, fiyat, stok, kategori_id, satici_id) VALUES
('Kulaklık BT', 750.00, 100,
 (SELECT id FROM e_ticaret.kategori WHERE ad='Elektronik'),
 (SELECT id FROM e_ticaret.satici   WHERE ad='TechnoStore')),
('Kot Pantolon', 599.90, 200,
 (SELECT id FROM e_ticaret.kategori WHERE ad='Moda'),
 (SELECT id FROM e_ticaret.satici   WHERE ad='ModaX')),
('Yastık', 89.90, 300,
 (SELECT id FROM e_ticaret.kategori WHERE ad='Ev & Yaşam'),
 (SELECT id FROM e_ticaret.satici   WHERE ad='HomePlus'));

---- 3. bölüm c kısmı


-- Sipariş oluştur (AYNI satırda id'yi yakalayıp detay ekleyelim)
WITH new_order AS (
  INSERT INTO e_ticaret.siparis (musteri_id, odeme_turu)
  VALUES (
    (SELECT id FROM e_ticaret.musteri WHERE email = 'ayse@example.com'),
    'KREDI_KARTI'
  )
  RETURNING id
)
INSERT INTO e_ticaret.siparis_detay (siparis_id, urun_id, adet, fiyat)
SELECT
  no.id AS siparis_id,
  u1.id AS urun_id, 2 AS adet, 750.00 AS fiyat
FROM new_order no
JOIN e_ticaret.urun u1 ON u1.ad = 'Kulaklık BT'
UNION ALL
SELECT
  no.id,
  u2.id, 3, 89.90
FROM new_order no
JOIN e_ticaret.urun u2 ON u2.ad = 'Yastık';

-- Güncelleme silme  stok düşürme  işlemleri

-- Fiyat güncelleme
UPDATE e_ticaret.urun SET fiyat = 800.00 WHERE ad = 'Kulaklık BT';

-- Stok düşürme
UPDATE e_ticaret.urun SET stok = stok - 2 WHERE ad = 'Kulaklık BT';

-- Sipariş detayı silme
DELETE FROM e_ticaret.siparis_detay
WHERE siparis_id = 1
  AND urun_id = (SELECT id FROM e_ticaret.urun WHERE ad = 'Yastık');

-- Rapor Sroguları

-- En çok sipariş veren 5 müşteri
SELECT m.ad, m.soyad, COUNT(s.id) AS siparis_sayisi
FROM e_ticaret.musteri m
JOIN e_ticaret.siparis s ON m.id = s.musteri_id
GROUP BY m.id
ORDER BY siparis_sayisi DESC
LIMIT 5;

-- En çok satılan ürünler
SELECT u.ad, SUM(d.adet) AS toplam_adet
FROM e_ticaret.urun u
JOIN e_ticaret.siparis_detay d ON u.id = d.urun_id
GROUP BY u.id
ORDER BY toplam_adet DESC;

-- En yüksek cirosu olan satıcılar
SELECT s.ad, SUM(d.adet * d.fiyat) AS ciro
FROM e_ticaret.satici s
JOIN e_ticaret.urun u ON s.id = u.satici_id
JOIN e_ticaret.siparis_detay d ON u.id = d.urun_id
GROUP BY s.id
ORDER BY ciro DESC;

-- Şehirlere göre müşteri sayısı
SELECT sehir, COUNT(*) AS musteri_sayisi
FROM e_ticaret.musteri
GROUP BY sehir;

-- Kategori bazlı toplam satışlar
SELECT k.ad AS kategori, SUM(d.adet * d.fiyat) AS toplam_satis
FROM e_ticaret.kategori k
JOIN e_ticaret.urun u ON k.id = u.kategori_id
JOIN e_ticaret.siparis_detay d ON u.id = d.urun_id
GROUP BY k.ad;

-- Aylara göre sipariş sayısı
SELECT DATE_TRUNC('month', s.tarih) AS ay, COUNT(*) AS siparis_sayisi
FROM e_ticaret.siparis s
GROUP BY DATE_TRUNC('month', s.tarih)
ORDER BY ay;

--Joinli Karma Sorgular

-- Siparişlerde müşteri + ürün + satıcı bilgisi
SELECT s.id AS siparis_id,
       m.ad AS musteri,
       u.ad AS urun,
       sa.ad AS satici,
       d.adet,
       d.fiyat
FROM e_ticaret.siparis s
JOIN e_ticaret.musteri m ON s.musteri_id = m.id
JOIN e_ticaret.siparis_detay d ON s.id = d.siparis_id
JOIN e_ticaret.urun u ON d.urun_id = u.id
JOIN e_ticaret.satici sa ON u.satici_id = sa.id;

-- Hiç satılmamış ürünler
SELECT u.ad
FROM e_ticaret.urun u
LEFT JOIN e_ticaret.siparis_detay d ON u.id = d.urun_id
WHERE d.id IS NULL;

-- Hiç sipariş vermemiş müşteriler
SELECT m.ad, m.soyad
FROM e_ticaret.musteri m
LEFT JOIN e_ticaret.siparis s ON m.id = s.musteri_id
WHERE s.id IS NULL;

---opsiyonel

-- En çok kazanç sağlayan ilk 3 kategori
SELECT k.ad,
       SUM(d.adet * d.fiyat) AS kazanc
FROM e_ticaret.kategori k
JOIN e_ticaret.urun u ON k.id = u.kategori_id
JOIN e_ticaret.siparis_detay d ON u.id = d.urun_id
GROUP BY k.ad
ORDER BY kazanc DESC
LIMIT 3;

-- Ortalama sipariş tutarını geçen siparişler
SELECT id, toplam_tutar
FROM e_ticaret.siparis
WHERE toplam_tutar > (SELECT AVG(toplam_tutar) FROM e_ticaret.siparis);

-- En az bir kez elektronik ürün alan müşteriler
SELECT DISTINCT m.ad, m.soyad
FROM e_ticaret.musteri m
JOIN e_ticaret.siparis s ON m.id = s.musteri_id
JOIN e_ticaret.siparis_detay d ON s.id = d.siparis_id
JOIN e_ticaret.urun u ON d.urun_id = u.id
JOIN e_ticaret.kategori k ON u.kategori_id = k.id
WHERE k.ad = 'Elektronik';


