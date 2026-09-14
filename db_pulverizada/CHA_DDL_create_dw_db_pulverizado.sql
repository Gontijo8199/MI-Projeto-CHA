DROP SCHEMA IF EXISTS dw_cha_pulverizado CASCADE;
CREATE SCHEMA dw_cha_pulverizado;

SET search_path=dw_cha_pulverizado;

CREATE TABLE Corretor_DIMENSION
(
  cor_SK BIGINT GENERATED ALWAYS AS IDENTITY,
  cor_CPF CHAR(11) NOT NULL,

  cor_registro VARCHAR(100) NOT NULL,
  cor_nome VARCHAR(255) NOT NULL,
  cor_sobrenome VARCHAR(255) NOT NULL,
 
  cor_dt_inicio TIMESTAMP NOT NULL,
  cor_dt_fim TIMESTAMP,
  cor_is_atual BOOLEAN NOT NULL,
 
  PRIMARY KEY (cor_SK)
);
 
CREATE TABLE Imovel_DIMENSION
(
  im_SK BIGINT GENERATED ALWAYS AS IDENTITY,
  im_ID INT NOT NULL,

  im_logradouro VARCHAR(255) NOT NULL,
  im_bairro VARCHAR(255) NOT NULL,
  im_cidade VARCHAR(100) NOT NULL,
  im_estado VARCHAR(100) NOT NULL,

  im_num_anuncios INT NOT NULL,
  im_gasto_em_anuncios FLOAT NOT NULL,
 
  im_dt_inicio TIMESTAMP NOT NULL,
  im_dt_fim TIMESTAMP,
  im_is_atual BOOLEAN NOT NULL,
 
  PRIMARY KEY (im_SK)
);
 
CREATE TABLE Cliente_DIMENSION
(
  cl_SK BIGINT GENERATED ALWAYS AS IDENTITY,
  cl_CPF CHAR(11) NOT NULL,
  cl_nome VARCHAR(255) NOT NULL,
  cl_sobrenome VARCHAR(255) NOT NULL,
 
  cl_dt_inicio TIMESTAMP NOT NULL,
  cl_dt_fim TIMESTAMP,
  cl_is_atual BOOLEAN NOT NULL,
 
  PRIMARY KEY (cl_SK)
);
 
CREATE TABLE Data_DIMENSION
(
  dt_SK INT NOT NULL,
  dt_data_completa DATE NOT NULL,
  dt_dia_semana INT NOT NULL,
  dt_dia_mes INT NOT NULL,
  dt_mes INT NOT NULL,
  dt_ano INT NOT NULL,
  dt_trimestre INT NOT NULL,
  PRIMARY KEY (dt_SK)
);
 
CREATE TABLE Trans_Venda_FACT
(
  tv_SK BIGINT GENERATED ALWAYS AS IDENTITY,
  tv_ID INT NOT NULL,

  tv_valor FLOAT NOT NULL,
  tv_valor_cliente FLOAT NOT NULL,
  
  tv_comissao FLOAT NOT NULL,

  tv_tipo_cliente VARCHAR(10) NOT NULL
    CHECK (tv_tipo_cliente IN ('COMPRADOR','VENDEDOR')),

  tv_total_compradores INT NOT NULL,
  tv_total_vendedores INT NOT NULL,

  cor_SK BIGINT NOT NULL,
  im_SK BIGINT NOT NULL,
  cl_SK BIGINT NOT NULL,
  dt_SK INT NOT NULL,

  PRIMARY KEY (tv_SK),
  FOREIGN KEY (cor_SK) REFERENCES Corretor_DIMENSION(cor_SK),
  FOREIGN KEY (im_SK) REFERENCES Imovel_DIMENSION(im_SK),
  FOREIGN KEY (cl_SK) REFERENCES Cliente_DIMENSION(cl_SK),
  FOREIGN KEY (dt_SK) REFERENCES Data_DIMENSION(dt_SK)
);
 
CREATE TABLE Receita_Agregada_FACT
(
  ra_SK BIGINT GENERATED ALWAYS AS IDENTITY,
  ra_comissao_total FLOAT NOT NULL,
  
  im_SK BIGINT NOT NULL,
  dt_SK INT NOT NULL,

  PRIMARY KEY (ra_SK),
  FOREIGN KEY (im_SK) REFERENCES Imovel_DIMENSION(im_SK),
  FOREIGN KEY (dt_SK) REFERENCES Data_DIMENSION(dt_SK)
);
 