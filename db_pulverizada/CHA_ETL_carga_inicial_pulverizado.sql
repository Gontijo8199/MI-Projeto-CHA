/*
-- CHA_ETL.sql
-- ETL: OLTP (schema oper_cha, ver CHA_DDL) -> DW (schema dw_cha_pulverizado)
-- Ordem: dimensões primeiro (por causa das FKs), fato(s) por último
*/

SET search_path=dw_cha_pulverizado;

-- 1) Data_DIMENSION
-- Grão: 1 linha por data distinta em que houve uma TransVenda
INSERT INTO Data_DIMENSION (dt_SK, dt_data_completa, dt_dia_semana, dt_dia_mes, dt_mes, dt_ano, dt_trimestre)
SELECT DISTINCT
    CAST(TO_CHAR(tv.TransVendaData, 'YYYYMMDD') AS INT)  AS dt_SK,
    tv.TransVendaData                                     AS dt_data_completa,
    EXTRACT(DOW  FROM tv.TransVendaData)::INT             AS dt_dia_semana,
    EXTRACT(DAY  FROM tv.TransVendaData)::INT             AS dt_dia_mes,
    EXTRACT(MONTH FROM tv.TransVendaData)::INT            AS dt_mes,
    EXTRACT(YEAR FROM tv.TransVendaData)::INT             AS dt_ano,
    EXTRACT(QUARTER FROM tv.TransVendaData)::INT          AS dt_trimestre
FROM oper_cha.TransVenda tv
ON CONFLICT (dt_SK) DO NOTHING;

-- 2) Corretor_DIMENSION (SCD Tipo 2 — carga inicial: tudo entra como versão atual)
INSERT INTO Corretor_DIMENSION (cor_CPF, cor_registro, cor_nome, cor_sobrenome, cor_dt_inicio, cor_dt_fim, cor_is_atual)
SELECT
    co.FuncCPF,
    co.CorretorRegistro,
    f.FuncPrimNome,
    f.FuncUltimoNome,
    CURRENT_TIMESTAMP AS cor_dt_inicio,
    NULL               AS cor_dt_fim,
    TRUE               AS cor_is_atual
FROM oper_cha.Corretor co
JOIN oper_cha.Funcionario f ON f.FuncCPF = co.FuncCPF;

-- 3) Cliente_DIMENSION (SCD Tipo 2 — carga inicial)
INSERT INTO Cliente_DIMENSION (cl_CPF, cl_nome, cl_sobrenome, cl_dt_inicio, cl_dt_fim, cl_is_atual)
SELECT
    c.ClienteCPF,
    c.ClientePrimNome,
    c.CliUltimoNome,
    CURRENT_TIMESTAMP AS cl_dt_inicio,
    NULL               AS cl_dt_fim,
    TRUE               AS cl_is_atual
FROM oper_cha.Cliente c;

-- 4) Imovel_DIMENSION (SCD Tipo 2 — carga inicial)
-- Endereço vem de Endereco -> CEP -> UF
-- Métricas de anúncio (im_num_anuncios, im_gasto_em_anuncios) são agregadas de Anuncio
INSERT INTO Imovel_DIMENSION (im_ID, im_logradouro, im_bairro, im_cidade, im_estado,
                               im_num_anuncios, im_gasto_em_anuncios,
                               im_dt_inicio, im_dt_fim, im_is_atual)
SELECT
    i.ImovelID,
    cep.NmLogradouro,
    e.EndBairro,
    cep.CEPMunicipio,
    uf.UFEstadoNome,
    COALESCE(anu.num_anuncios, 0)   AS im_num_anuncios,
    COALESCE(anu.gasto_total, 0)    AS im_gasto_em_anuncios,
    CURRENT_TIMESTAMP AS im_dt_inicio,
    NULL               AS im_dt_fim,
    TRUE               AS im_is_atual
FROM oper_cha.Imovel i
JOIN oper_cha.Endereco e ON e.EndID = i.EndID
JOIN oper_cha.CEP cep    ON cep.CEP = e.CEP
JOIN oper_cha.UF uf      ON uf.UF = cep.UF
LEFT JOIN (
    SELECT ImovelID,
           COUNT(*)              AS num_anuncios,
           SUM(AnuncioPreco)     AS gasto_total
    FROM oper_cha.Anuncio
    GROUP BY ImovelID
) anu ON anu.ImovelID = i.ImovelID;

-- 5) Trans_Venda_FACT
-- Grão: 1 linha por cliente envolvido na transação de venda
INSERT INTO Trans_Venda_FACT (
    tv_ID, tv_valor, tv_valor_cliente, 
    tv_comissao, tv_comissao_cliente, tv_tipo_cliente,
    tv_total_compradores, tv_total_vendedores,
    cor_SK, im_SK, cl_SK, dt_SK
)
WITH base AS (
    SELECT
        tv.TransVendaID,
        tv.TransVendaValor,
        tv.TransComissao,
        tv.TransVendaData,
        tv.FuncCPF,
        it.ImovelID,
        (SELECT COUNT(*) FROM oper_cha.ClienteCompra cc
          WHERE cc.TransVendaID = tv.TransVendaID) AS total_compradores,
        (SELECT COUNT(*) FROM oper_cha.ClienteVende cv
          WHERE cv.TransVendaID = tv.TransVendaID) AS total_vendedores
    FROM oper_cha.TransVenda tv
    JOIN oper_cha.ImovelTransacao it
        ON it.TransVendaID = tv.TransVendaID
),
participantes AS (
    SELECT 
        b.TransVendaID, b.TransVendaValor, b.TransComissao, b.TransVendaData, b.FuncCPF, b.ImovelID, 
        b.total_compradores, b.total_vendedores, cc.ClienteCPF AS ClienteCPF, 'COMPRADOR' AS tipo_cliente
    FROM base b
    JOIN oper_cha.ClienteCompra cc ON cc.TransVendaID = b.TransVendaID

    UNION ALL

    SELECT 
        b.TransVendaID, b.TransVendaValor, b.TransComissao, b.TransVendaData, b.FuncCPF, b.ImovelID, 
        b.total_compradores, b.total_vendedores, cv.ClienteCPF AS ClienteCPF, 'VENDEDOR' AS tipo_cliente
    FROM base b
    JOIN oper_cha.ClienteVende cv ON cv.TransVendaID = b.TransVendaID
)
SELECT
    p.TransVendaID,
    p.TransVendaValor,

    CASE
        WHEN p.tipo_cliente = 'COMPRADOR' THEN p.TransVendaValor / p.total_compradores
        WHEN p.tipo_cliente = 'VENDEDOR' THEN p.TransVendaValor / p.total_vendedores
        ELSE NULL
    END,

    CASE
        WHEN p.tipo_cliente = 'COMPRADOR' THEN p.TransComissao / p.total_compradores
        WHEN p.tipo_cliente = 'VENDEDOR' THEN p.TransComissao / p.total_vendedores
        ELSE NULL
    END,

    p.TransComissao,
    p.tipo_cliente,
    p.total_compradores,
    p.total_vendedores,
    cor.cor_SK,
    im.im_SK,
    cl.cl_SK,
    dt.dt_SK
FROM participantes p
JOIN Corretor_DIMENSION cor
    ON cor.cor_CPF = p.FuncCPF
   AND cor.cor_is_atual = TRUE
JOIN Imovel_DIMENSION im
    ON im.im_ID = p.ImovelID
   AND im.im_is_atual = TRUE
JOIN Cliente_DIMENSION cl
    ON cl.cl_CPF = p.ClienteCPF
   AND cl.cl_is_atual = TRUE
JOIN Data_DIMENSION dt
    ON dt.dt_data_completa = p.TransVendaData;

-- 6) Receita_Agregada_FACT
-- Grão: 1 linha por (imóvel, dia)
INSERT INTO Receita_Agregada_FACT (ra_comissao_total, im_SK, dt_SK)
SELECT
    SUM(tv.TransComissao) AS ra_comissao_total,
    im.im_SK,
    dt.dt_SK
FROM oper_cha.TransVenda tv
JOIN oper_cha.ImovelTransacao it ON it.TransVendaID = tv.TransVendaID
JOIN Imovel_DIMENSION im ON im.im_ID = it.ImovelID AND im.im_is_atual = TRUE
JOIN Data_DIMENSION dt ON dt.dt_data_completa = tv.TransVendaData
GROUP BY im.im_SK, dt.dt_SK;




-- Criação do tabelas audit para o overhead de mudanças
CREATE SCHEMA IF NOT EXISTS audit;
SET search_path = audit;

-- Tabelas de "chaves alteradas": o trigger só avisa QUAL entidade mudou.
-- O ETL sempre relê o estado ATUAL em oper_cha filtrando por essas chaves
-- (nunca aplica um "payload antigo" enfileirado).

CREATE TABLE chg_funcionario (
    seq       BIGSERIAL PRIMARY KEY,
    func_cpf  CHAR(11) NOT NULL,
    acao      CHAR(1) NOT NULL CHECK (acao IN ('I','U')),
    tstamp    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE chg_corretor (
    seq       BIGSERIAL PRIMARY KEY,
    func_cpf  CHAR(11) NOT NULL,
    acao      CHAR(1) NOT NULL CHECK (acao IN ('I','U')),
    tstamp    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE chg_cliente (
    seq          BIGSERIAL PRIMARY KEY,
    cliente_cpf  CHAR(11) NOT NULL,
    acao         CHAR(1) NOT NULL CHECK (acao IN ('I','U')),
    tstamp       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE chg_imovel (
    seq        BIGSERIAL PRIMARY KEY,
    imovel_id  INT NOT NULL,
    acao       CHAR(1) NOT NULL CHECK (acao IN ('I','U')),
    tstamp     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- TransVenda é fato imutável (sem UPDATE na origem) -> só insert-mirror
CREATE TABLE ins_transvenda (
    seq            BIGSERIAL PRIMARY KEY,
    transvenda_id  INT NOT NULL,
    tstamp         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Criação de triggers
CREATE OR REPLACE FUNCTION audit.trg_chg_funcionario() RETURNS trigger AS $$
BEGIN
    INSERT INTO audit.chg_funcionario(func_cpf, acao)
    VALUES (NEW.FuncCPF, substring(TG_OP,1,1));
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, oper_cha, audit;

CREATE TRIGGER funcionario_chg_trg
AFTER INSERT OR UPDATE ON oper_cha.Funcionario
FOR EACH ROW EXECUTE PROCEDURE audit.trg_chg_funcionario();

CREATE OR REPLACE FUNCTION audit.trg_chg_corretor() RETURNS trigger AS $$
BEGIN
    INSERT INTO audit.chg_corretor(func_cpf, acao)
    VALUES (NEW.FuncCPF, substring(TG_OP,1,1));
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, oper_cha, audit;

CREATE TRIGGER corretor_chg_trg
AFTER INSERT OR UPDATE ON oper_cha.Corretor
FOR EACH ROW EXECUTE PROCEDURE audit.trg_chg_corretor();

CREATE OR REPLACE FUNCTION audit.trg_chg_cliente() RETURNS trigger AS $$
BEGIN
    INSERT INTO audit.chg_cliente(cliente_cpf, acao)
    VALUES (NEW.ClienteCPF, substring(TG_OP,1,1));
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, oper_cha, audit;

CREATE TRIGGER cliente_chg_trg
AFTER INSERT OR UPDATE ON oper_cha.Cliente
FOR EACH ROW EXECUTE PROCEDURE audit.trg_chg_cliente();

-- Imovel_DIMENSION: mudança direta no Imovel...
CREATE OR REPLACE FUNCTION audit.trg_chg_imovel() RETURNS trigger AS $$
BEGIN
    INSERT INTO audit.chg_imovel(imovel_id, acao)
    VALUES (NEW.ImovelID, substring(TG_OP,1,1));
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, oper_cha, audit;

CREATE TRIGGER imovel_chg_trg
AFTER INSERT OR UPDATE ON oper_cha.Imovel
FOR EACH ROW EXECUTE PROCEDURE audit.trg_chg_imovel();

-- ...ou mudança indireta via novo Anuncio (afeta os campos agregados)
CREATE OR REPLACE FUNCTION audit.trg_chg_imovel_por_anuncio() RETURNS trigger AS $$
BEGIN
    INSERT INTO audit.chg_imovel(imovel_id, acao) VALUES (NEW.ImovelID, 'U');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, oper_cha, audit;

CREATE TRIGGER anuncio_chg_imovel_trg
AFTER INSERT ON oper_cha.Anuncio
FOR EACH ROW EXECUTE PROCEDURE audit.trg_chg_imovel_por_anuncio();

-- TransVenda é imutável -> só marcamos o insert
CREATE OR REPLACE FUNCTION audit.trg_ins_transvenda() RETURNS trigger AS $$
BEGIN
    INSERT INTO audit.ins_transvenda(transvenda_id) VALUES (NEW.TransVendaID);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, oper_cha, audit;

CREATE TRIGGER transvenda_ins_trg
AFTER INSERT ON oper_cha.TransVenda
FOR EACH ROW EXECUTE PROCEDURE audit.trg_ins_transvenda();