/*
-- CHA_F2_DDL_fipezap.sql  (Fase II)
-- Estende o DW da Fase 1 (schema dw_cha_pulverizado, modelo Pulverizado) com o benchmark de mercado FipeZAP.
-- Pré-requisito: CHA_DDL_create_dw_db_pulverizado.sql + CHA_ETL_carga_inicial_pulverizado.sql já executados.
-- Pode ser executado mais de uma vez (idempotente).
*/
SET search_path = dw_cha_pulverizado;

-- 0) Normalização de nome de cidade (sem acento, maiúsculo) - chave de junção OLTP/DW x FipeZAP
CREATE OR REPLACE FUNCTION fn_norm_cidade(t TEXT) RETURNS TEXT AS $$
  SELECT UPPER(TRANSLATE(TRIM(t),
    'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ',
    'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC'));
$$ LANGUAGE SQL IMMUTABLE;

-- 1) Staging: espelho do CSV da camada silver do data lake (recarregada a cada carga)
CREATE TABLE IF NOT EXISTS stg_fipezap (
  cidade        VARCHAR(100),
  cidade_norm   VARCHAR(100),
  mes           DATE,
  dormitorios   VARCHAR(5),
  preco_m2      FLOAT,
  var_mensal    FLOAT,
  var_12m       FLOAT
);

-- 2) Nova dimensão: Mercado_FIPEZAP_DIMENSION
-- Grão: 1 linha por (cidade, mês, faixa de dormitórios). Apartamentos prontos, venda residencial.
-- Tipo 1 (sobrescreve): a Fipe revisa a série; não há histórico de versões a preservar.
CREATE TABLE IF NOT EXISTS Mercado_FIPEZAP_DIMENSION (
  mk_SK          BIGINT GENERATED ALWAYS AS IDENTITY,
  mk_cidade      VARCHAR(100) NOT NULL,
  mk_cidade_norm VARCHAR(100) NOT NULL,
  mk_mes         DATE         NOT NULL,   -- sempre dia 1
  mk_dormitorios VARCHAR(5)   NOT NULL,   -- Total | 1D | 2D | 3D | 4D (4D = 4 ou mais)
  mk_preco_m2    FLOAT        NOT NULL,   -- R$/m² anunciado
  mk_var_mensal  FLOAT,
  mk_var_12m     FLOAT,
  mk_dt_carga    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (mk_SK),
  UNIQUE (mk_cidade_norm, mk_mes, mk_dormitorios)
);

-- 3) Imovel_DIMENSION: atributos necessários para calcular R$/m² e casar a faixa de dormitórios
ALTER TABLE Imovel_DIMENSION ADD COLUMN IF NOT EXISTS im_tipo         VARCHAR(100);
ALTER TABLE Imovel_DIMENSION ADD COLUMN IF NOT EXISTS im_qtd_quartos  INT;
ALTER TABLE Imovel_DIMENSION ADD COLUMN IF NOT EXISTS im_m2           INT;

-- 4) Trans_Venda_FACT: medida derivada + FK para o benchmark (NULL quando não há cobertura)
ALTER TABLE Trans_Venda_FACT ADD COLUMN IF NOT EXISTS tv_valor_m2 FLOAT;
ALTER TABLE Trans_Venda_FACT ADD COLUMN IF NOT EXISTS mk_SK BIGINT;
DO $$ BEGIN
  ALTER TABLE Trans_Venda_FACT
    ADD CONSTRAINT fk_tv_mercado FOREIGN KEY (mk_SK) REFERENCES Mercado_FIPEZAP_DIMENSION(mk_SK);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- 5) View de consumo do dashboard: nossa venda x mercado
-- Grão: 1 linha por venda. A fato pulverizada tem 1 linha por (venda x cliente), mas tv_valor, tv_comissao,
-- imóvel, corretor, data e mk_SK são da venda inteira e se repetem; sem o DISTINCT ON o ágio médio
-- pesaria cada venda pelo número de clientes.
DROP VIEW IF EXISTS vw_venda_vs_mercado;
CREATE VIEW vw_venda_vs_mercado AS
SELECT DISTINCT ON (f.tv_ID)
  f.tv_ID,
  f.tv_total_compradores, f.tv_total_vendedores,
  dt.dt_data_completa,
  cor.cor_nome || ' ' || cor.cor_sobrenome AS corretor,
  im.im_cidade, im.im_estado, im.im_bairro, im.im_tipo, im.im_qtd_quartos, im.im_m2,
  f.tv_valor, f.tv_comissao, f.tv_valor_m2,
  mk.mk_preco_m2,
  mk.mk_var_12m,
  CASE WHEN mk.mk_preco_m2 IS NOT NULL
       THEN f.tv_valor_m2 / mk.mk_preco_m2 - 1 END AS agio_vs_mercado   -- +10% = vendemos 10% acima do mercado anunciado
FROM Trans_Venda_FACT f
JOIN Imovel_DIMENSION im ON im.im_SK = f.im_SK
JOIN Data_DIMENSION   dt ON dt.dt_SK = f.dt_SK
JOIN Corretor_DIMENSION cor ON cor.cor_SK = f.cor_SK
LEFT JOIN Mercado_FIPEZAP_DIMENSION mk ON mk.mk_SK = f.mk_SK
ORDER BY f.tv_ID;
